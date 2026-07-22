import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

Future<void> main(List<String> arguments) async {
  if (arguments.length < 3 || arguments.length > 5) {
    stderr.writeln(
      'Usage: animation_review.dart <catalog.json> <animations-dir> '
      '<output.html> [dictionary-id] [clip-ids]',
    );
    exitCode = 64;
    return;
  }
  final catalog = jsonDecode(await File(arguments[0]).readAsString()) as Map;
  final directory = Directory(arguments[1]);
  final initialDictionary = arguments.length >= 4 ? arguments[3] : '';
  final initialClipIds = arguments.length == 5 ? arguments[4] : '';
  final dictionaryOrder = int.tryParse(initialDictionary);
  final hierarchies = <int, List<int>>{};
  await for (final entity in directory.list()) {
    if (entity is! File || !entity.path.split('/').last.startsWith('skin_')) {
      continue;
    }
    final skin = jsonDecode(await entity.readAsString()) as Map;
    final frames = skin['frames'] as List;
    if (frames.isEmpty) continue;
    final hierarchy = (frames.first as Map)['hierarchy'];
    if (hierarchy is! Map) continue;
    final bones = hierarchy['bones'] as List;
    hierarchies.putIfAbsent(
      bones.length,
      () =>
          _parents(bones.map((bone) => (bone as Map)['flags'] as int).toList()),
    );
  }

  final cards = StringBuffer();
  final clips = List<Map>.from(catalog['clips'] as List);
  if (dictionaryOrder != null) {
    clips.sort(
      (a, b) => _slotForDictionary(
        a,
        dictionaryOrder,
      ).compareTo(_slotForDictionary(b, dictionaryOrder)),
    );
  }
  for (final clip in clips) {
    final id = clip['id'] as String;
    final animation =
        jsonDecode(
              await File('${directory.path}/$id.animation.json').readAsString(),
            )
            as Map;
    final samples = _reviewSamples(animation, count: 7);
    final parents = hierarchies[animation['nodeCount'] as int];
    final memberships = (clip['dictionaryMemberships'] as List)
        .map((value) => 'D${(value as Map)['dictionaryId']}:S${value['slot']}')
        .join(', ');
    final owners = (clip['ownerCandidates'] as List? ?? const [])
        .map((value) => (value as Map)['ownerClass'])
        .toSet()
        .join(', ');
    final status = clip['status'] as String;
    final action = clip['action'] as String?;
    cards.write(
      '<article data-id="$id" data-dictionaries="${_dictionaryIds(clip)}" '
      'data-nodes="${animation['nodeCount']}"><h2>$id</h2>'
      '<p>${animation['duration'].toStringAsFixed(3)} s · '
      '${animation['nodeCount']} nodes · ${htmlEscape.convert(memberships)}'
      '${owners.isEmpty ? '' : ' · ${htmlEscape.convert(owners)}'} · '
      '<strong class="$status">$status</strong>'
      '${action == null ? '' : ' · ${htmlEscape.convert(action)}'}</p>',
    );
    if (parents == null) {
      cards.write('<p class="missing">No matching hierarchy</p>');
    } else {
      for (final sample in samples) {
        cards.write(_poseSvg(sample as Map, parents));
      }
    }
    cards.write('</article>');
  }

  final output = File(arguments[2]);
  await output.parent.create(recursive: true);
  await output.writeAsString('''<!doctype html>
<html><head><meta charset="utf-8"><title>Animation review</title><style>
body{margin:0;background:#101218;color:#eef;font:14px system-ui}header{position:sticky;top:0;z-index:2;background:#181c26;padding:12px;display:flex;gap:12px;align-items:center}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(560px,1fr));gap:10px;padding:10px}article{background:#1b202c;border:1px solid #343b4c;border-radius:8px;padding:10px}h2{margin:0;font-size:20px}p{margin:4px 0 8px;color:#aeb8cc}svg{background:#080a0f;border-radius:4px;margin-right:4px}.bone{stroke:#70d6ff;stroke-width:1.5}.joint{fill:#ffca3a}.missing{color:#ff7777}.confirmed{color:#7ee787}.provisional{color:#e3b341}.unreviewed{color:#ff7b72}
</style></head><body><header><strong>345 animation clips</strong><label>Dictionary <input id="dictionary" size="5" placeholder="all"></label><label>Nodes <input id="nodes" size="5" placeholder="all"></label><label>Clips <input id="clips" size="18" placeholder="0000,0001"></label><button onclick="filter()">Filter</button><span id="count"></span></header><main>$cards</main><script>
function filter(){const d=document.querySelector('#dictionary').value.trim(),n=document.querySelector('#nodes').value.trim(),ids=new Set(document.querySelector('#clips').value.split(',').map(x=>x.trim()).filter(Boolean));let count=0;document.querySelectorAll('article').forEach(e=>{const show=(!d||e.dataset.dictionaries.split(',').includes(d))&&(!n||e.dataset.nodes===n)&&(!ids.size||ids.has(e.dataset.id));e.hidden=!show;if(show)count++});document.querySelector('#count').textContent=count+' shown'}
const query=new URLSearchParams(location.search||location.hash.slice(1));document.querySelector('#dictionary').value=query.get('dictionary')||'$initialDictionary';document.querySelector('#nodes').value=query.get('nodes')||'';document.querySelector('#clips').value=query.get('clips')||'$initialClipIds';filter();
</script></body></html>''');
  stdout.writeln('Wrote ${output.path}');
}

int _slotForDictionary(Map clip, int dictionaryId) {
  for (final rawMembership in clip['dictionaryMemberships'] as List) {
    final membership = rawMembership as Map;
    if (membership['dictionaryId'] == dictionaryId) {
      return membership['slot'] as int;
    }
  }
  return 0x7FFFFFFF;
}

List<Map<String, Object>> _reviewSamples(Map animation, {required int count}) {
  final duration = (animation['duration'] as num).toDouble();
  return List.generate(count, (index) {
    final time = count == 1 ? 0.0 : duration * index / (count - 1);
    return {
      'time': time,
      'localTransforms': _sampleLocalTransforms(animation, time),
    };
  });
}

List<List<double>> _sampleLocalTransforms(Map animation, double time) {
  final nodeCount = animation['nodeCount'] as int;
  final keyFrameSize = animation['keyFrameSize'] as int;
  final frames = animation['frames'] as List;
  final current = List<int>.generate(nodeCount, (node) => nodeCount + node);
  for (var frame = nodeCount * 2; frame < frames.length; frame++) {
    var earliestNode = 0;
    for (var node = 1; node < nodeCount; node++) {
      if (_frameTime(frames[current[node]]) <
          _frameTime(frames[current[earliestNode]])) {
        earliestNode = node;
      }
    }
    if (_frameTime(frames[current[earliestNode]]) >= time) break;
    current[earliestNode] = frame;
  }
  return current
      .map((frameIndex) {
        final b = frames[frameIndex] as Map;
        final previous = (b['previousFrame'] as int) ~/ keyFrameSize;
        if (previous < 0 || previous >= frames.length) {
          throw FormatException(
            'Animation previous-frame pointer is outside the clip: $previous',
          );
        }
        final a = frames[previous] as Map;
        final aTime = _frameTime(a);
        final bTime = _frameTime(b);
        final span = bTime - aTime;
        final alpha = span == 0 ? 0.0 : ((time - aTime) / span).clamp(0.0, 1.0);
        final translation = List<double>.generate(
          3,
          (index) =>
              (a['translation'][index] as num).toDouble() +
              ((b['translation'][index] as num).toDouble() -
                      (a['translation'][index] as num).toDouble()) *
                  alpha,
        );
        final quaternion = List<double>.generate(
          4,
          (index) =>
              (a['quaternion'][index] as num).toDouble() +
              ((b['quaternion'][index] as num).toDouble() -
                      (a['quaternion'][index] as num).toDouble()) *
                  alpha,
        );
        final length = math.sqrt(
          quaternion.fold<double>(0, (sum, value) => sum + value * value),
        );
        if (length > 0) {
          for (var index = 0; index < quaternion.length; index++) {
            quaternion[index] /= length;
          }
        }
        return _transformMatrix(quaternion, translation);
      })
      .toList(growable: false);
}

double _frameTime(Object? frame) =>
    (((frame as Map)['time']) as num).toDouble();

List<double> _transformMatrix(
  List<double> quaternion,
  List<double> translation,
) {
  final x = quaternion[0];
  final y = quaternion[1];
  final z = quaternion[2];
  final w = quaternion[3];
  return [
    1 - 2 * (y * y + z * z),
    2 * (x * y + z * w),
    2 * (x * z - y * w),
    0,
    2 * (x * y - z * w),
    1 - 2 * (x * x + z * z),
    2 * (y * z + x * w),
    0,
    2 * (x * z + y * w),
    2 * (y * z - x * w),
    1 - 2 * (x * x + y * y),
    0,
    translation[0],
    translation[1],
    translation[2],
    1,
  ];
}

String _dictionaryIds(Map clip) => (clip['dictionaryMemberships'] as List)
    .map((value) => ((value as Map)['dictionaryId']).toString())
    .toSet()
    .join(',');

List<int> _parents(List<int> flags) {
  final result = List.filled(flags.length, -1);
  final stack = <int>[];
  var current = -1;
  for (var i = 0; i < flags.length; i++) {
    result[i] = current;
    if ((flags[i] & 2) != 0) {
      stack.add(current);
    }
    current = i;
    if ((flags[i] & 1) != 0) {
      current = stack.isEmpty ? -1 : stack.removeLast();
    }
  }
  return result;
}

String _poseSvg(Map sample, List<int> parents) {
  final local = (sample['localTransforms'] as List)
      .map(
        (matrix) =>
            (matrix as List).map((value) => (value as num).toDouble()).toList(),
      )
      .toList();
  final world = <List<double>>[];
  for (var i = 0; i < local.length; i++) {
    world.add(
      parents[i] < 0 ? local[i] : _multiply(world[parents[i]], local[i]),
    );
  }
  final points = world.map((matrix) => [matrix[12], matrix[13]]).toList();
  final minX = points.map((p) => p[0]).reduce(math.min);
  final maxX = points.map((p) => p[0]).reduce(math.max);
  final minY = points.map((p) => p[1]).reduce(math.min);
  final maxY = points.map((p) => p[1]).reduce(math.max);
  final scale = math.min(
    104 / math.max(maxX - minX, .001),
    124 / math.max(maxY - minY, .001),
  );
  String xy(List<double> point) =>
      '${12 + (point[0] - minX) * scale},${138 - (point[1] - minY) * scale}';
  final lines = StringBuffer();
  for (var i = 0; i < points.length; i++) {
    if (parents[i] >= 0) {
      lines.write(
        '<line class="bone" x1="${xy(points[parents[i]]).split(',')[0]}" y1="${xy(points[parents[i]]).split(',')[1]}" x2="${xy(points[i]).split(',')[0]}" y2="${xy(points[i]).split(',')[1]}"/>',
      );
    }
  }
  for (final point in points) {
    final position = xy(point).split(',');
    lines.write(
      '<circle class="joint" cx="${position[0]}" cy="${position[1]}" r="1.7"/>',
    );
  }
  return '<svg viewBox="0 0 128 150" width="72" height="84">$lines<text x="4" y="12" fill="#ccd" font-size="9">t=${(sample['time'] as num).toStringAsFixed(2)}</text></svg>';
}

List<double> _multiply(List<double> a, List<double> b) {
  final result = List.filled(16, 0.0);
  for (var column = 0; column < 4; column++) {
    for (var row = 0; row < 4; row++) {
      for (var k = 0; k < 4; k++) {
        result[column * 4 + row] += a[k * 4 + row] * b[column * 4 + k];
      }
    }
  }
  return result;
}

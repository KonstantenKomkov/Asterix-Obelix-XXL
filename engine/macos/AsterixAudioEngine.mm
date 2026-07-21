#import "AsterixAudioEngine.h"

#import <AVFoundation/AVFoundation.h>

static uint16_t ReadU16(const uint8_t* bytes) { return bytes[0] | ((uint16_t)bytes[1] << 8); }
static uint32_t ReadU32(const uint8_t* bytes) {
  return bytes[0] | ((uint32_t)bytes[1] << 8) | ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

@implementation AsterixAudioEngine {
  AVAudioEngine* _engine;
  AVAudioEnvironmentNode* _environment;
  AVAudioPlayerNode* _music;
  AVAudioPlayerNode* _ambience;
  NSArray<AVAudioPlayerNode*>* _effects;
  AVAudioPCMBuffer* _imported;
  float _musicVolume;
  float _effectsVolume;
  BOOL _bedsStarted;
}

- (instancetype)init {
  if ((self = [super init])) {
    _musicVolume = _effectsVolume = .8f;
    _engine = [[AVAudioEngine alloc] init];
    _environment = [[AVAudioEnvironmentNode alloc] init];
    _music = [[AVAudioPlayerNode alloc] init];
    _ambience = [[AVAudioPlayerNode alloc] init];
    NSMutableArray* effects = [NSMutableArray array];
    for (NSUInteger i = 0; i < 8; ++i) [effects addObject:[[AVAudioPlayerNode alloc] init]];
    _effects = effects;
    [_engine attachNode:_environment];
    [_engine attachNode:_music];
    [_engine attachNode:_ambience];
    for (AVAudioPlayerNode* player in _effects) [_engine attachNode:player];
    [_engine connect:_environment to:_engine.mainMixerNode format:nil];
    AVAudioFormat* effectFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:24000 channels:1];
    for (AVAudioPlayerNode* player in _effects) [_engine connect:player to:_environment format:effectFormat];
    _environment.distanceAttenuationParameters.referenceDistance = 2;
    _environment.distanceAttenuationParameters.maximumDistance = 35;
    _environment.distanceAttenuationParameters.rolloffFactor = 1;
  }
  return self;
}

- (BOOL)ready { return _imported != nil; }
- (NSUInteger)activeEffectCount {
  NSUInteger result = 0;
  for (AVAudioPlayerNode* player in _effects) if (player.playing) ++result;
  return result;
}

- (BOOL)loadWaveData:(NSData*)data error:(NSError**)error {
  const uint8_t* bytes = (const uint8_t*)data.bytes;
  if (data.length < 44 || memcmp(bytes, "RIFF", 4) || memcmp(bytes + 8, "WAVE", 4)) {
    if (error) *error = [NSError errorWithDomain:@"AsterixAudio" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Audio payload is not RIFF/WAVE"}];
    return NO;
  }
  uint16_t channels = 0, bits = 0, formatTag = 0;
  uint32_t sampleRate = 0;
  const uint8_t* pcm = nullptr;
  uint32_t pcmLength = 0;
  for (NSUInteger offset = 12; offset + 8 <= data.length;) {
    uint32_t length = ReadU32(bytes + offset + 4);
    if (length > data.length - offset - 8) break;
    if (!memcmp(bytes + offset, "fmt ", 4) && length >= 16) {
      formatTag = ReadU16(bytes + offset + 8);
      channels = ReadU16(bytes + offset + 10);
      sampleRate = ReadU32(bytes + offset + 12);
      bits = ReadU16(bytes + offset + 22);
    } else if (!memcmp(bytes + offset, "data", 4)) {
      pcm = bytes + offset + 8;
      pcmLength = length;
    }
    offset += 8 + length + (length & 1);
  }
  if (formatTag != 1 || channels == 0 || channels > 2 || bits != 16 || sampleRate == 0 || pcm == nullptr) {
    if (error) *error = [NSError errorWithDomain:@"AsterixAudio" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Only mono/stereo PCM16 WAV is supported"}];
    return NO;
  }
  AVAudioFormat* format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:sampleRate channels:channels interleaved:NO];
  AVAudioFrameCount frames = pcmLength / (channels * 2);
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frames];
  buffer.frameLength = frames;
  const int16_t* samples = (const int16_t*)pcm;
  for (AVAudioChannelCount channel = 0; channel < channels; ++channel)
    for (AVAudioFrameCount frame = 0; frame < frames; ++frame)
      buffer.floatChannelData[channel][frame] = samples[frame * channels + channel] / 32768.0f;
  _imported = buffer;
  [_engine connect:_music to:_engine.mainMixerNode format:format];
  [_engine connect:_ambience to:_environment format:format];
  NSError* startError = nil;
  if (!_engine.running && ![_engine startAndReturnError:&startError]) {
    if (error) *error = startError;
    return NO;
  }
  return YES;
}

- (void)setMusicVolume:(float)music effectsVolume:(float)effects {
  _musicVolume = fminf(1, fmaxf(0, music));
  _effectsVolume = fminf(1, fmaxf(0, effects));
  _music.volume = _musicVolume;
  _ambience.volume = _effectsVolume * .35f;
}

- (void)setListenerPosition:(vector_float3)position forward:(vector_float3)forward {
  _environment.listenerPosition = (AVAudio3DPoint){position.x, position.y, position.z};
  _environment.listenerAngularOrientation = AVAudioMake3DAngularOrientation(atan2f(forward.x, forward.z) * 180 / M_PI, 0, 0);
}

- (void)startBeds {
  if (!_imported || _bedsStarted) return;
  _bedsStarted = YES;
  [_music scheduleBuffer:_imported atTime:nil options:AVAudioPlayerNodeBufferLoops completionHandler:nil];
  [_ambience scheduleBuffer:_imported atTime:nil options:AVAudioPlayerNodeBufferLoops completionHandler:nil];
  _music.volume = _musicVolume;
  _ambience.volume = _effectsVolume * .18f;
  _ambience.position = (AVAudio3DPoint){0, 0, 8};
  [_music play];
  [_ambience play];
}

- (AVAudioPCMBuffer*)toneForCue:(NSUInteger)cue {
  const double rate = 24000;
  const AVAudioFrameCount frames = (AVAudioFrameCount)(rate * (.075 + MIN(cue, 9) * .009));
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:rate channels:1];
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frames];
  buffer.frameLength = frames;
  float frequency = 120 + cue * 45;
  for (AVAudioFrameCount i = 0; i < frames; ++i) {
    float envelope = 1.0f - (float)i / frames;
    buffer.floatChannelData[0][i] = sinf(2 * M_PI * frequency * i / rate) * envelope * .22f;
  }
  return buffer;
}

- (void)playCue:(NSUInteger)cue channel:(NSUInteger)channel position:(vector_float3)position spatial:(BOOL)spatial gain:(float)gain {
  if (!_engine.running) [self resume];
  AVAudioPlayerNode* player = _effects[channel % _effects.count];
  [player stop];
  player.renderingAlgorithm = spatial ? AVAudio3DMixingRenderingAlgorithmHRTF : AVAudio3DMixingRenderingAlgorithmEqualPowerPanning;
  player.position = (AVAudio3DPoint){position.x, position.y, position.z};
  player.volume = _effectsVolume * fminf(1, fmaxf(0, gain));
  [player scheduleBuffer:[self toneForCue:cue] completionHandler:nil];
  [player play];
}

- (void)suspend { [_engine pause]; }
- (void)resume {
  if (!_engine.running && _imported) { NSError* error = nil; [_engine startAndReturnError:&error]; }
}
- (void)stop {
  [_music stop]; [_ambience stop];
  for (AVAudioPlayerNode* player in _effects) [player stop];
  [_engine stop];
  _bedsStarted = NO;
}

@end

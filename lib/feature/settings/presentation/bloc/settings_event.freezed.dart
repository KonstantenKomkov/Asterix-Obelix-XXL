// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SettingsEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SettingsEvent()';
}


}

/// @nodoc
class $SettingsEventCopyWith<$Res>  {
$SettingsEventCopyWith(SettingsEvent _, $Res Function(SettingsEvent) __);
}


/// Adds pattern-matching-related methods to [SettingsEvent].
extension SettingsEventPatterns on SettingsEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SettingsLoadRequested value)?  loadRequested,TResult Function( SettingsChanged value)?  changed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SettingsLoadRequested() when loadRequested != null:
return loadRequested(_that);case SettingsChanged() when changed != null:
return changed(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SettingsLoadRequested value)  loadRequested,required TResult Function( SettingsChanged value)  changed,}){
final _that = this;
switch (_that) {
case SettingsLoadRequested():
return loadRequested(_that);case SettingsChanged():
return changed(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SettingsLoadRequested value)?  loadRequested,TResult? Function( SettingsChanged value)?  changed,}){
final _that = this;
switch (_that) {
case SettingsLoadRequested() when loadRequested != null:
return loadRequested(_that);case SettingsChanged() when changed != null:
return changed(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  loadRequested,TResult Function( GameSettings settings)?  changed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SettingsLoadRequested() when loadRequested != null:
return loadRequested();case SettingsChanged() when changed != null:
return changed(_that.settings);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  loadRequested,required TResult Function( GameSettings settings)  changed,}) {final _that = this;
switch (_that) {
case SettingsLoadRequested():
return loadRequested();case SettingsChanged():
return changed(_that.settings);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  loadRequested,TResult? Function( GameSettings settings)?  changed,}) {final _that = this;
switch (_that) {
case SettingsLoadRequested() when loadRequested != null:
return loadRequested();case SettingsChanged() when changed != null:
return changed(_that.settings);case _:
  return null;

}
}

}

/// @nodoc


class SettingsLoadRequested implements SettingsEvent {
  const SettingsLoadRequested();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsLoadRequested);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SettingsEvent.loadRequested()';
}


}




/// @nodoc


class SettingsChanged implements SettingsEvent {
  const SettingsChanged(this.settings);
  

 final  GameSettings settings;

/// Create a copy of SettingsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsChangedCopyWith<SettingsChanged> get copyWith => _$SettingsChangedCopyWithImpl<SettingsChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsChanged&&(identical(other.settings, settings) || other.settings == settings));
}


@override
int get hashCode => Object.hash(runtimeType,settings);

@override
String toString() {
  return 'SettingsEvent.changed(settings: $settings)';
}


}

/// @nodoc
abstract mixin class $SettingsChangedCopyWith<$Res> implements $SettingsEventCopyWith<$Res> {
  factory $SettingsChangedCopyWith(SettingsChanged value, $Res Function(SettingsChanged) _then) = _$SettingsChangedCopyWithImpl;
@useResult
$Res call({
 GameSettings settings
});




}
/// @nodoc
class _$SettingsChangedCopyWithImpl<$Res>
    implements $SettingsChangedCopyWith<$Res> {
  _$SettingsChangedCopyWithImpl(this._self, this._then);

  final SettingsChanged _self;
  final $Res Function(SettingsChanged) _then;

/// Create a copy of SettingsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? settings = null,}) {
  return _then(SettingsChanged(
null == settings ? _self.settings : settings // ignore: cast_nullable_to_non_nullable
as GameSettings,
  ));
}


}

// dart format on

import 'photo_picker_config_stub.dart'
    if (dart.library.io) 'photo_picker_config_io.dart' as implementation;

/// Enables the privacy-preserving Android Photo Picker where supported.
/// Other platforms use a no-op implementation without Android runtime APIs.
bool configurePhotoPicker() => implementation.configurePhotoPicker();

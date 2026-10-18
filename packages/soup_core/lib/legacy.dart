/// Only the legacy app (apps/android) uses these: its Drift-backed offline
/// metadata and artwork caches and the view models on top of them. The v2
/// app has its own catalog. Delete this library, `src/legacy/`,
/// `test/legacy/` and the drift dependencies when the legacy app goes.
library;

export 'src/legacy/artwork_cache.dart';
export 'src/legacy/details_view_model.dart';
export 'src/legacy/jellyfin_metadata_repository.dart';
export 'src/legacy/library_view_model.dart';
export 'src/legacy/soup_database.dart';

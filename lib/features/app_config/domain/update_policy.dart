/// What the app must do about its own version.
enum UpdateRequirement {
  /// Nothing to do.
  none,

  /// A newer version exists; the user may update or dismiss.
  optional,

  /// This version is no longer supported; the app must be blocked until the
  /// user updates.
  required,
}

/// Decides whether the running app must / may be updated.
class UpdatePolicy {
  const UpdatePolicy._();

  static List<int>? _parseVersion(String version) {
    if (version.trim().isEmpty) return null;
    final parts = version.split('.');
    final segments = <int>[];
    for (final part in parts) {
      if (part.isEmpty) return null;
      final val = int.tryParse(part);
      // Disallow negative numbers or non-numeric strings
      if (val == null || val < 0) return null;
      segments.add(val);
    }
    return segments;
  }

  static int _compareVersions(List<int> a, List<int> b) {
    final maxLength = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < maxLength; i++) {
      final valA = i < a.length ? a[i] : 0;
      final valB = i < b.length ? b[i] : 0;
      if (valA != valB) {
        return valA.compareTo(valB);
      }
    }
    return 0;
  }

  static UpdateRequirement evaluate({
    required String currentVersion,
    required String minSupportedVersion,
    required String latestVersion,
  }) {
    try {
      final current = _parseVersion(currentVersion);
      final minSupported = _parseVersion(minSupportedVersion);
      final latest = _parseVersion(latestVersion);

      // If any version is malformed, fail safe to 'none' so users aren't locked out
      if (current == null || minSupported == null || latest == null) {
        return UpdateRequirement.none;
      }

      if (_compareVersions(current, minSupported) < 0) {
        return UpdateRequirement.required;
      }
      if (_compareVersions(current, latest) < 0) {
        return UpdateRequirement.optional;
      }
      return UpdateRequirement.none;
    } catch (_) {
      return UpdateRequirement.none;
    }
  }
}
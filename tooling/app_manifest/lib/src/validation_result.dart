final class ManifestIssue {
  const ManifestIssue({
    required this.code,
    required this.message,
    required this.location,
  });

  final String code;
  final String message;
  final String location;

  @override
  String toString() => 'ERROR [$code] $message ($location)';
}

final class ManifestValidationResult {
  final List<ManifestIssue> issues = [];

  bool get isValid => issues.isEmpty;

  void error(String code, String message, String location) {
    issues.add(
      ManifestIssue(code: code, message: message, location: location),
    );
  }
}

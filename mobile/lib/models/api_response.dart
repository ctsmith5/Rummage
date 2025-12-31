class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;
  final Map<String, String>? errors;

  ApiResponse({
    required this.success,
    this.data,
    this.error,
    this.errors,
  });

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromJsonT,
  ) {
    return ApiResponse(
      success: json['success'] as bool,
      data: json['data'] != null && fromJsonT != null
          ? fromJsonT(json['data'])
          : null,
      error: json['error'] as String?,
      errors: json['errors'] != null
          ? Map<String, String>.from(json['errors'] as Map)
          : null,
    );
  }

  bool get isSuccess => success && error == null;
  bool get isError => !success || error != null;

  String get errorMessage => error ?? 'An unknown error occurred';
}


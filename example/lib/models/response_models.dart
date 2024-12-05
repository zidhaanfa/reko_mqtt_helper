import 'dart:convert';

class ResponseModel {
  const ResponseModel({
    required this.data,
    required this.hasError,
    this.statusCode,
  });

  factory ResponseModel.message(
    String message, {
    bool isSuccess = false,
    int? statusCode,
  }) =>
      ResponseModel(
        data: jsonEncode({'message': message}),
        hasError: !isSuccess,
        statusCode: statusCode,
      );

  factory ResponseModel.fromMap(Map<String, dynamic> map) => ResponseModel(
        data: map['data'] as String,
        hasError: map['hasError'] as bool,
        statusCode: map['statusCode'] != null ? map['statusCode'] as int : null,
      );

  factory ResponseModel.fromJson(String source) =>
      ResponseModel.fromMap(json.decode(source) as Map<String, dynamic>);

  final String data;
  final bool hasError;
  final int? statusCode;

  ResponseModel copyWith({
    String? data,
    bool? hasError,
    int? statusCode,
  }) =>
      ResponseModel(
        data: data ?? this.data,
        hasError: hasError ?? this.hasError,
        statusCode: statusCode ?? this.statusCode,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'data': data,
        'hasError': hasError,
        'statusCode': statusCode,
      };

  String toJson() => json.encode(toMap());

  @override
  String toString() =>
      'ResponseModel(data: $data, hasError: $hasError, statusCode: $statusCode)';

  @override
  bool operator ==(covariant ResponseModel other) {
    if (identical(this, other)) return true;

    return other.data == data &&
        other.hasError == hasError &&
        other.statusCode == statusCode;
  }

  @override
  int get hashCode => data.hashCode ^ hasError.hashCode ^ statusCode.hashCode;
}

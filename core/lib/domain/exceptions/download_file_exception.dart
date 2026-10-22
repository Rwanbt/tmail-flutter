import 'package:core/domain/exceptions/app_base_exception.dart';

abstract class DownloadFileException extends AppBaseException {
  const DownloadFileException(super.message);
}

class CommonDownloadFileException extends DownloadFileException {
  const CommonDownloadFileException(super.message);

  @override
  String get exceptionName => 'CommonDownloadFileException';
}

class CancelDownloadFileException extends DownloadFileException {
  const CancelDownloadFileException(super.message);

  @override
  String get exceptionName => 'CancelDownloadFileException';
}

/// The transfer ended before the whole attachment was received.
///
/// A partial file is never handed to the caller: it would be saved, shared or
/// printed as if it were the complete attachment.
class IncompleteDownloadFileException extends DownloadFileException {
  const IncompleteDownloadFileException(super.message);

  @override
  String get exceptionName => 'IncompleteDownloadFileException';
}

class DeviceNotSupportedException extends DownloadFileException {
  const DeviceNotSupportedException()
      : super('This device is not supported, please try on Android or iOS');

  @override
  String get exceptionName => 'DeviceNotSupportedException';
}

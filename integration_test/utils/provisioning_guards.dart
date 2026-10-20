import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:dartz/dartz.dart';
import 'package:tmail_ui_user/features/composer/domain/state/send_email_state.dart';

/// Missing test mail identities are fixture failures, not an empty inbox.
T requireProvisioningIdentity<T extends Object>(T? identity) {
  if (identity == null) {
    throw StateError('E2E email provisioning has no sending identity');
  }
  return identity;
}

/// Waits until the provisioned email submission finishes successfully.
///
/// Never include a failure's exception, email subject, address, or attachments
/// in the diagnostic: backend failures may contain private request details.
Future<void> requireProvisioningSendSuccess(
  Stream<Either<Failure, Success>> outcomes,
) async {
  Either<Failure, Success>? lastOutcome;
  await for (final outcome in outcomes) {
    lastOutcome = outcome;
  }

  if (lastOutcome == null) {
    throw StateError('E2E email provisioning emitted no send result');
  }

  lastOutcome.fold(
    (failure) => throw StateError(
      'E2E email provisioning failed (${failure.runtimeType})',
    ),
    (success) {
      if (success is! SendEmailSuccess) {
        throw StateError(
          'E2E email provisioning did not complete (${success.runtimeType})',
        );
      }
    },
  );
}

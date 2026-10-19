import 'dart:async';

import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:model/email/email_action_type.dart';
import 'package:tmail_ui_user/features/composer/domain/model/email_request.dart';
import 'package:tmail_ui_user/features/composer/domain/state/send_email_state.dart';

import '../../integration_test/utils/provisioning_guards.dart';

void main() {
  final sendSuccess = SendEmailSuccess(
    emailRequest: EmailRequest(
      email: Email(),
      emailActionType: EmailActionType.compose,
    ),
  );

  test('missing sender identity fails immediately', () {
    expect(
      () => requireProvisioningIdentity<Object>(null),
      throwsA(isA<StateError>()),
    );
  });

  test('available sender identity is preserved without mutation', () {
    final identity = Object();
    expect(requireProvisioningIdentity(identity), same(identity));
  });

  test('a backend send failure fails immediately without exposing secrets',
      () async {
    const privateToken = 'private-access-token-should-not-be-logged';
    final outcomes = Stream<Either<Failure, Success>>.value(
      Left(SendEmailFailure(exception: StateError(privateToken))),
    );

    await expectLater(
      requireProvisioningSendSuccess(outcomes),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'safe diagnostic',
          allOf(contains('SendEmailFailure'), isNot(contains(privateToken))),
        ),
      ),
    );
  });

  test('an unfinished send is not mistaken for successful provisioning',
      () async {
    await expectLater(
      requireProvisioningSendSuccess(
        Stream<Either<Failure, Success>>.value(Right(SendEmailLoading())),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('an empty send stream fails instead of waiting for the inbox', () async {
    await expectLater(
      requireProvisioningSendSuccess(
        const Stream<Either<Failure, Success>>.empty(),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('provisioning waits for terminal successful submission', () async {
    final source = StreamController<Either<Failure, Success>>();
    var completed = false;
    final provisioning = requireProvisioningSendSuccess(source.stream).then(
      (_) => completed = true,
    );

    source.add(Right(SendEmailLoading()));
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    source.add(Right(sendSuccess));
    await source.close();
    await provisioning;
    expect(completed, isTrue);
  });
}

import 'package:core/presentation/resources/image_paths.dart';
import 'package:core/presentation/views/text/middle_ellipsis_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmail_ui_user/features/composer/presentation/widgets/attachment_item_composer_widget.dart';
import 'package:tmail_ui_user/features/upload/domain/model/upload_task_id.dart';
import 'package:tmail_ui_user/features/upload/presentation/model/upload_file_status.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations_delegate.dart';

void main() {
  group('AttachmentItemComposerWidget test', () {
    testWidgets('shows the attachment name without bidi overrides', (tester) async {
      final imagePaths = ImagePaths();

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [AppLocalizationsDelegate()],
        home: Scaffold(
          body: AttachmentItemComposerWidget(
            imagePaths: imagePaths,
            fileIcon: imagePaths.icCancel,
            fileName: 'invoice\u202Efdp.exe',
            fileSize: '1 KB',
            uploadStatus: UploadFileStatus.succeed,
            percentUploading: 1,
            uploadTaskId: const UploadTaskId('id'),
          ),
        ),
      ));

      final label = tester.widget<MiddleEllipsisText>(find.byType(MiddleEllipsisText));
      expect(label.text, 'invoicefdp.exe');
    });

    testWidgets('exposes distinct localized remove and preview actions without bidi spoofing', (tester) async {
      final semantics = tester.ensureSemantics();
      final imagePaths = ImagePaths();
      final removed = <UploadTaskId>[];
      final previewed = <UploadTaskId>[];
      const taskId = UploadTaskId('attachment-123');

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [AppLocalizationsDelegate()],
        home: Scaffold(
          body: AttachmentItemComposerWidget(
            imagePaths: imagePaths,
            fileIcon: imagePaths.icCancel,
            fileName: 'report\u202Efdp.exe',
            fileSize: '2 KB',
            uploadStatus: UploadFileStatus.succeed,
            percentUploading: 1,
            uploadTaskId: taskId,
            onDeleteAttachmentAction: removed.add,
            onPreviewAttachmentAction: previewed.add,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final translations = AppLocalizations.of(tester.element(find.byType(AttachmentItemComposerWidget)));
      final removeLabel = '${translations.remove}: reportfdp.exe';
      final previewLabel = '${translations.preview}: reportfdp.exe';
      expect(find.byTooltip(removeLabel), findsOneWidget);
      expect(find.bySemanticsLabel(previewLabel), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('\u202E')), findsNothing);

      await tester.tap(find.byTooltip(removeLabel));
      expect(removed, [taskId]);
      expect(previewed, isEmpty);

      await tester.tap(find.bySemanticsLabel(previewLabel));
      expect(previewed, [taskId]);
      expect(removed, [taskId]);
      semantics.dispose();
    });
  });
}

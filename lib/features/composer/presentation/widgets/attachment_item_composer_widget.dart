import 'package:core/presentation/resources/image_paths.dart';
import 'package:core/presentation/views/button/tmail_button_widget.dart';
import 'package:core/presentation/views/text/middle_ellipsis_text.dart';
import 'package:flutter/material.dart';
import 'package:core/presentation/extensions/string_extension.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tmail_ui_user/features/base/mixin/app_loader_mixin.dart';
import 'package:tmail_ui_user/features/composer/presentation/styles/attachment_item_composer_widget_style.dart';
import 'package:tmail_ui_user/features/composer/presentation/widgets/attachment_progress_loading_composer_widget.dart';
import 'package:tmail_ui_user/features/upload/domain/model/upload_task_id.dart';
import 'package:tmail_ui_user/features/upload/presentation/model/upload_file_status.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';

typedef OnDeleteAttachmentAction = void Function(UploadTaskId uploadTaskId);
typedef OnPreviewAttachmentAction = void Function(UploadTaskId uploadTaskId);

class AttachmentItemComposerWidget extends StatelessWidget with AppLoaderMixin {

  final ImagePaths imagePaths;
  final String fileIcon;
  final String fileName;
  final String fileSize;
  final UploadFileStatus uploadStatus;
  final double percentUploading;
  final UploadTaskId uploadTaskId;
  final double? maxWidth;
  final EdgeInsetsGeometry? itemMargin;
  final EdgeInsetsGeometry? itemPadding;
  final OnDeleteAttachmentAction? onDeleteAttachmentAction;
  final OnPreviewAttachmentAction? onPreviewAttachmentAction;
  final Widget? buttonAction;

  const AttachmentItemComposerWidget({
    super.key,
    required this.imagePaths,
    required this.fileIcon,
    required this.fileName,
    required this.fileSize,
    required this.uploadStatus,
    required this.percentUploading,
    required this.uploadTaskId,
    this.maxWidth,
    this.itemMargin,
    this.itemPadding,
    this.buttonAction,
    this.onDeleteAttachmentAction,
    this.onPreviewAttachmentAction,
  });

  @override
  Widget build(BuildContext context) {
    // Screen readers and hover users need a named action for each attachment.
    // Use the same bidi-safe name that the visible row renders.
    final accessibleName = fileName.sanitizedBidiForDisplay;
    final translations = AppLocalizations.of(context);
    Widget bodyItem = Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SvgPicture.asset(
                      fileIcon,
                      width: AttachmentItemComposerWidgetStyle.iconSize,
                      height: AttachmentItemComposerWidgetStyle.iconSize,
                      fit: BoxFit.fill
                  ),
                  const SizedBox(width: AttachmentItemComposerWidgetStyle.space),
                  Flexible(
                      child: MiddleEllipsisText(
                        fileName.sanitizedBidiForDisplay,
                        style: AttachmentItemComposerWidgetStyle.labelTextStyle,
                        preserveFileExtension: true,
                      )
                  ),
                  const SizedBox(width: AttachmentItemComposerWidgetStyle.space),
                  Text(
                      fileSize,
                      style: AttachmentItemComposerWidgetStyle.sizeLabelTextStyle
                  ),
                ],
              ),
              AttachmentProgressLoadingComposerWidget(
                uploadStatus: uploadStatus,
                percentUploading: percentUploading,
              )
            ],
          ),
        ),
        const SizedBox(width: AttachmentItemComposerWidgetStyle.space),
        if (onDeleteAttachmentAction != null)
          TMailButtonWidget.fromIcon(
          icon: imagePaths.icCancel,
          tooltipMessage: '${translations.remove}: $accessibleName',
          iconSize: AttachmentItemComposerWidgetStyle.deleteIconSize,
          borderRadius: AttachmentItemComposerWidgetStyle.deleteIconRadius,
          padding: AttachmentItemComposerWidgetStyle.deleteIconPadding,
          iconColor: AttachmentItemComposerWidgetStyle.deleteIconColor,
          onTapActionCallback: () => onDeleteAttachmentAction!(uploadTaskId),
        )
      ],
    );

    if (onPreviewAttachmentAction != null) {
      bodyItem = Semantics(
        container: true,
        explicitChildNodes: true,
        button: true,
        label: '${translations.preview}: $accessibleName',
        onTap: () => onPreviewAttachmentAction!(uploadTaskId),
        child: InkWell(
          excludeFromSemantics: true,
          onTap: () => onPreviewAttachmentAction!(uploadTaskId),
          child: bodyItem,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(AttachmentItemComposerWidgetStyle.radius)),
        border: Border.all(color: AttachmentItemComposerWidgetStyle.borderColor),
        color: AttachmentItemComposerWidgetStyle.backgroundColor
      ),
      width: AttachmentItemComposerWidgetStyle.width,
      padding: itemPadding ?? AttachmentItemComposerWidgetStyle.padding,
      margin: itemMargin,
      child: bodyItem,
    );
  }
}

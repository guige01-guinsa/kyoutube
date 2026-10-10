import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../auth/application/auth_providers.dart';
import '../data/business_document_store.dart';
import '../domain/business_registration.dart';
import 'shopping_assistant_dialogs.dart';

final businessDocumentPickerProvider =
    Provider<Future<Uint8List?> Function()>((_) => () async {
          final file = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 2048,
              maxHeight: 2048,
              imageQuality: 90);
          if (file == null) return null;
          if (await file.length() > businessDocumentMaxBytes) {
            throw const FormatException('Image too large');
          }
          return file.readAsBytes();
        });

class BusinessRegistrationInput extends ConsumerStatefulWidget {
  const BusinessRegistrationInput(
      {super.key,
      required this.title,
      required this.value,
      required this.onChanged,
      required this.onUploaded,
      required this.onBusyChanged,
      this.enabled = true});
  final String title;
  final BusinessRegistration value;
  final ValueChanged<BusinessRegistration> onChanged;
  final ValueChanged<String> onUploaded;
  final ValueChanged<bool> onBusyChanged;
  final bool enabled;
  @override
  ConsumerState<BusinessRegistrationInput> createState() =>
      _BusinessRegistrationInputState();
}

class _BusinessRegistrationInputState
    extends ConsumerState<BusinessRegistrationInput> {
  bool _busy = false;
  String? _error;
  String t(String ko, String en) => shopText(context, ko, en);
  Future<void> _pick() async {
    final owner = ref.read(activeAccountIdProvider);
    if (owner == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.onBusyChanged(true);
    try {
      final raw = await ref.read(businessDocumentPickerProvider)();
      if (raw == null ||
          !mounted ||
          ref.read(activeAccountIdProvider) != owner) {
        return;
      }
      final png = await prepareBusinessDocument(raw);
      if (!mounted || ref.read(activeAccountIdProvider) != owner) return;
      final store = ref.read(businessDocumentStoreProvider);
      final path = await store.upload(png);
      if (!mounted || ref.read(activeAccountIdProvider) != owner) {
        try {
          await store.discard(path);
        } catch (_) {/* Remains private. */}
        return;
      }
      widget.onUploaded(path);
      widget.onChanged(
          BusinessRegistration(number: widget.value.number, imagePath: path));
    } catch (_) {
      if (mounted) {
        setState(() => _error = t(
            '사진을 등록하지 못했습니다. 5MB 이하 이미지를 선택하고 연결 상태를 확인해 주세요.',
            'Could not upload. Choose an image up to 5 MB and check your connection.'));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextFormField(
                initialValue: widget.value.number,
                maxLength: 12,
                enabled: widget.enabled && !_busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: t('사업자등록번호 (선택)',
                        'Business registration number (optional)'),
                    hintText: '000-00-00000'),
                onChanged: (value) => widget.onChanged(BusinessRegistration(
                    number: value, imagePath: widget.value.imagePath)),
                validator: (_) => widget.value.valid
                    ? null
                    : t('사업자등록번호 10자리를 입력해 주세요.',
                        'Enter the 10-digit business registration number.')),
            Wrap(spacing: 8, runSpacing: 4, children: [
              OutlinedButton.icon(
                  onPressed: widget.enabled && !_busy ? _pick : null,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(widget.value.imagePath.isEmpty
                      ? t('등록증 사진 추가', 'Add certificate photo')
                      : t('등록증 사진 변경', 'Replace certificate photo'))),
              if (widget.value.imagePath.isNotEmpty) ...[
                TextButton(
                    onPressed: _busy
                        ? null
                        : () => showBusinessDocument(context,
                            title: widget.title, registration: widget.value),
                    child: Text(t('사진 보기', 'View photo'))),
                TextButton(
                    onPressed: widget.enabled && !_busy
                        ? () => widget.onChanged(
                            BusinessRegistration(number: widget.value.number))
                        : null,
                    child: Text(t('사진 제외', 'Remove photo'))),
              ],
            ]),
            Text(
                t('작성한 계정만 보관·조회합니다. PDF에 사본을 넣을지는 출력 전에 선택합니다.',
                    'Private to your account. Choose whether to attach a copy before PDF export or printing.'),
                style: Theme.of(context).textTheme.bodySmall),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ])));
}

class BusinessRegistrationLink extends StatelessWidget {
  const BusinessRegistrationLink(
      {super.key, required this.title, required this.registration});
  final String title;
  final BusinessRegistration registration;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(registration.formattedNumber),
        trailing: registration.imagePath.isEmpty
            ? null
            : const Icon(Icons.image_outlined),
        onTap: registration.imagePath.isEmpty
            ? null
            : () => showBusinessDocument(context,
                title: title, registration: registration),
      );
}

Future<void> showBusinessDocument(BuildContext context,
        {required String title, required BusinessRegistration registration}) =>
    showDialog<void>(
        context: context,
        builder: (_) => ShoppingAccountGuard(
            child: _BusinessDocumentViewer(
                title: title, registration: registration)));

class _BusinessDocumentViewer extends ConsumerStatefulWidget {
  const _BusinessDocumentViewer(
      {required this.title, required this.registration});
  final String title;
  final BusinessRegistration registration;
  @override
  ConsumerState<_BusinessDocumentViewer> createState() =>
      _BusinessDocumentViewerState();
}

class _BusinessDocumentViewerState
    extends ConsumerState<_BusinessDocumentViewer> {
  late final _owner = ref.read(activeAccountIdProvider);
  late final _image = _load();
  MemoryImage? _provider;
  Future<MemoryImage> _load() async {
    final bytes = await ref
        .read(businessDocumentStoreProvider)
        .download(widget.registration.imagePath);
    if (!mounted ||
        _owner == null ||
        ref.read(activeAccountIdProvider) != _owner) {
      throw StateError('Account changed');
    }
    return _provider = MemoryImage(bytes);
  }

  @override
  void dispose() {
    _provider?.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
      child: Scaffold(
          appBar: AppBar(
              title: Text(widget.title),
              leading: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: shopText(context, '닫기', 'Close'),
                  onPressed: () => Navigator.pop(context))),
          body: Column(children: [
            Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(widget.registration.formattedNumber)),
            Expanded(
                child: FutureBuilder<MemoryImage>(
                    future: _image,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(
                            child: Text(shopText(
                                context,
                                '등록증을 열지 못했습니다. 연결 상태를 확인하고 다시 열어 주세요.',
                                'Could not open the certificate. Check your connection and reopen it.')));
                      }
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return InteractiveViewer(
                          minScale: 1,
                          maxScale: 5,
                          child: Center(
                              child: Image(
                                  image: snap.data!, fit: BoxFit.contain)));
                    })),
          ])));
}

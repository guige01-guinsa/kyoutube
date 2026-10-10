import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'workspace_menu.dart';

class WorkspaceDataNotice extends StatelessWidget {
  const WorkspaceDataNotice({super.key, required this.supplier});
  final bool supplier;
  @override
  Widget build(BuildContext context) => Material(
      color: const Color(0xfff3f4ef),
      child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Icon(supplier ? Icons.storefront_outlined : Icons.person_outline,
                  size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                      supplier
                          ? workspaceText(
                              context,
                              '공급업체 관리 · 공개한 업체·상품 정보는 회원에게 표시됩니다.',
                              'Supplier management · published business and products are visible to members.')
                          : workspaceText(
                              context,
                              '개인 작업실 · 이 계정의 자료이며 업소에 자동 공유되지 않습니다.',
                              'Personal studio · these records are not automatically shared with your business.'),
                      key: const Key('workspace-data-notice'),
                      style: Theme.of(context).textTheme.bodySmall)),
              IconButton(
                  tooltip:
                      workspaceText(context, '작업 공간 선택', 'Choose work area'),
                  onPressed: () => context.go('/workspace'),
                  icon: const Icon(Icons.swap_horiz)),
            ]),
          )));
}

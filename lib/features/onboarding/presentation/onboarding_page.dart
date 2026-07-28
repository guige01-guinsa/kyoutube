import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ops/ops_monitor_service.dart';
import '../application/onboarding_state.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    this.returnTo = '/',
  });

  final String returnTo;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    OpsMonitorService.recordEventCounter('onboarding.viewed');
  }

  static const List<_OnboardingSlide> _slides = <_OnboardingSlide>[
    _OnboardingSlide(
      icon: Icons.auto_awesome_outlined,
      title: 'AI 요약으로 빠르게 시작',
      description: '레시피 핵심을 짧게 요약하고, 주의사항과 팁을 바로 확인할 수 있어요.',
    ),
    _OnboardingSlide(
      icon: Icons.restaurant_menu_outlined,
      title: '재료부터 조리 순서까지 한 번에',
      description: '재료 체크, 조리 단계, 개인 레시피 복사까지 한 화면에서 이어집니다.',
    ),
    _OnboardingSlide(
      icon: Icons.account_circle_outlined,
      title: '계정 연결로 기록을 안전하게',
      description: '로그인 후 북마크와 피드백을 저장해 더 정확한 AI 보조를 받을 수 있어요.',
    ),
  ];

  bool get _isLastPage => _currentPage == _slides.length - 1;

  Future<void> _complete() async {
    if (_submitting) {
      return;
    }

    await OpsMonitorService.recordEventCounter('onboarding.completed');

    setState(() {
      _submitting = true;
    });

    await OnboardingState.markCompleted();
    if (!mounted) {
      return;
    }

    final target = widget.returnTo.startsWith('/') ? widget.returnTo : '/';
    context.go(target);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('환영합니다'),
        actions: <Widget>[
          TextButton(
            onPressed: _submitting
                ? null
                : () async {
                    await OpsMonitorService.recordEventCounter(
                      'onboarding.skipped',
                    );
                    await _complete();
                  },
            child: const Text('건너뛰기'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            children: <Widget>[
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _slides.length,
                  onPageChanged: (int index) {
                    final previous = _currentPage;
                    setState(() {
                      _currentPage = index;
                    });
                    if (index > previous) {
                      OpsMonitorService.recordEventCounter(
                        'onboarding.next_step',
                      );
                    }
                  },
                  itemBuilder: (BuildContext context, int index) {
                    final slide = _slides[index];
                    return _OnboardingSlideView(slide: slide);
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(_slides.length, (int index) {
                  final selected = index == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: selected ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting
                      ? null
                      : () async {
                          if (_isLastPage) {
                            await _complete();
                            return;
                          }
                          await _pageController.nextPage(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          );
                        },
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_isLastPage
                          ? Icons.rocket_launch_outlined
                          : Icons.arrow_forward),
                  label: Text(_isLastPage ? '바로 시작' : '다음'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlideView extends StatelessWidget {
  const _OnboardingSlideView({required this.slide});

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        CircleAvatar(
          radius: 44,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            slide.icon,
            size: 36,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          slide.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          slide.description,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

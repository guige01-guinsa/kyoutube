class PasswordPolicy {
  const PasswordPolicy._();

  static const int minimumLength = 8;

  static PasswordStrength evaluate(String password) {
    final hasMinimumLength = password.length >= minimumLength;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
    final hasNumber = RegExp(r'\d').hasMatch(password);
    final hasSpecialCharacter =
        RegExp(r'''[!@#$%^&*()_+\-=\[\]{};:'",.<>/?\\|`~]''')
            .hasMatch(password);
    final hasLongLength = password.length >= 12;

    var score = 0;

    if (hasMinimumLength) {
      score++;
    }
    if (hasLetter) {
      score++;
    }
    if (hasNumber) {
      score++;
    }
    if (hasSpecialCharacter || hasLongLength) {
      score++;
    }

    return PasswordStrength(
      score: score,
      hasMinimumLength: hasMinimumLength,
      hasLetter: hasLetter,
      hasNumber: hasNumber,
      hasSpecialCharacter: hasSpecialCharacter,
      hasLongLength: hasLongLength,
    );
  }

  static String? validateForSignUp(String? value) {
    final password = value ?? '';
    final result = evaluate(password);

    if (!result.hasMinimumLength) {
      return '비밀번호는 $minimumLength자 이상 입력해 주세요.';
    }

    if (!result.hasLetter) {
      return '비밀번호에 영문을 포함해 주세요.';
    }

    if (!result.hasNumber) {
      return '비밀번호에 숫자를 포함해 주세요.';
    }

    return null;
  }

  static String? validateForLogin(String? value) {
    if ((value ?? '').isEmpty) {
      return '비밀번호를 입력해 주세요.';
    }

    return null;
  }
}

class PasswordStrength {
  const PasswordStrength({
    required this.score,
    required this.hasMinimumLength,
    required this.hasLetter,
    required this.hasNumber,
    required this.hasSpecialCharacter,
    required this.hasLongLength,
  });

  final int score;
  final bool hasMinimumLength;
  final bool hasLetter;
  final bool hasNumber;
  final bool hasSpecialCharacter;
  final bool hasLongLength;

  bool get isValidForSignUp => hasMinimumLength && hasLetter && hasNumber;

  String get label {
    if (score <= 1) {
      return '약함';
    }

    if (score == 2) {
      return '보통';
    }

    if (score == 3) {
      return '좋음';
    }

    return '강함';
  }
}

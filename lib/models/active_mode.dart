enum ActiveMode {
  freeTime,
  homework,
  bedtime,
  school,
  custom;

  String get displayName {
    switch (this) {
      case ActiveMode.freeTime:
        return 'Free Time';
      case ActiveMode.homework:
        return 'Homework Time';
      case ActiveMode.bedtime:
        return 'Bedtime';
      case ActiveMode.school:
        return 'School Hours';
      case ActiveMode.custom:
        return 'Custom Schedule';
    }
  }

  String get emoji {
    switch (this) {
      case ActiveMode.freeTime:
        return '☀️';
      case ActiveMode.homework:
        return '📚';
      case ActiveMode.bedtime:
        return '🌙';
      case ActiveMode.school:
        return '🏫';
      case ActiveMode.custom:
        return '⏰';
    }
  }

  String get explanation {
    switch (this) {
      case ActiveMode.freeTime:
        return 'Enjoy your free time! 🎉';
      case ActiveMode.homework:
        return 'Some apps are paused to help you focus 💪';
      case ActiveMode.bedtime:
        return 'Time to wind down and rest 🌙';
      case ActiveMode.school:
        return 'Focus on learning during school hours 📖';
      case ActiveMode.custom:
        return 'A custom schedule is active ⏰';
    }
  }

  String get colorHex {
    switch (this) {
      case ActiveMode.freeTime:
        return '#10B981';
      case ActiveMode.homework:
        return '#3B82F6';
      case ActiveMode.bedtime:
        return '#8B5CF6';
      case ActiveMode.school:
        return '#F59E0B';
      case ActiveMode.custom:
        return '#6B7280';
    }
  }
}

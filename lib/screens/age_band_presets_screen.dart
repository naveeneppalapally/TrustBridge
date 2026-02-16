import 'package:flutter/material.dart';
import 'package:trustbridge_app/models/child_profile.dart';
import 'package:trustbridge_app/models/policy.dart';
import 'package:trustbridge_app/models/schedule.dart';

class AgeBandPresetsScreen extends StatelessWidget {
  const AgeBandPresetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final infoBg = isDark ? const Color(0xFF172638) : const Color(0xFFEFF7FF);
    final infoBorder =
        isDark ? Colors.blue.withValues(alpha: 0.35) : const Color(0xFFBFDBFE);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Age Band Guide'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Choose Age-Appropriate Protection',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Each age band includes carefully designed content filters and time restrictions.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
          ),
          const SizedBox(height: 20),
          _buildComparisonTable(context),
          const SizedBox(height: 20),
          _buildAgeBandCard(
            context,
            ageBand: AgeBand.young,
            title: '6-9 Years',
            subtitle: 'Young Children',
            description:
                'Strictest filters to create a safe, age-appropriate online environment.',
            icon: Icons.child_care,
            color: Colors.blue,
          ),
          const SizedBox(height: 12),
          _buildAgeBandCard(
            context,
            ageBand: AgeBand.middle,
            title: '10-13 Years',
            subtitle: 'Middle Schoolers',
            description:
                'Balanced protection that allows exploration while blocking inappropriate content.',
            icon: Icons.school,
            color: Colors.green,
          ),
          const SizedBox(height: 12),
          _buildAgeBandCard(
            context,
            ageBand: AgeBand.teen,
            title: '14-17 Years',
            subtitle: 'Teenagers',
            description:
                'Trust-based approach focusing on dangerous content while respecting growing independence.',
            icon: Icons.face,
            color: Colors.orange,
          ),
          const SizedBox(height: 20),
          _buildPhilosophySection(context),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: infoBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: infoBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'All presets can be customized later to match your family needs.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonTable(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF172638) : const Color(0xFFEFF7FF);
    final borderColor =
        isDark ? Colors.blue.withValues(alpha: 0.35) : const Color(0xFFBFDBFE);
    final young = Policy.presetForAgeBand(AgeBand.young);
    final middle = Policy.presetForAgeBand(AgeBand.middle);
    final teen = Policy.presetForAgeBand(AgeBand.teen);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Comparison',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Compare all age bands side-by-side before choosing one.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 56,
              columns: const [
                DataColumn(label: Text('Preset')),
                DataColumn(label: Text('6-9')),
                DataColumn(label: Text('10-13')),
                DataColumn(label: Text('14-17')),
              ],
              rows: [
                DataRow(
                  cells: [
                    const DataCell(Text('Blocked categories')),
                    DataCell(Text('${young.blockedCategories.length}')),
                    DataCell(Text('${middle.blockedCategories.length}')),
                    DataCell(Text('${teen.blockedCategories.length}')),
                  ],
                ),
                DataRow(
                  cells: [
                    const DataCell(Text('Bedtime window')),
                    DataCell(
                        Text(_scheduleWindow(young, ScheduleType.bedtime))),
                    DataCell(
                        Text(_scheduleWindow(middle, ScheduleType.bedtime))),
                    DataCell(Text(_scheduleWindow(teen, ScheduleType.bedtime))),
                  ],
                ),
                DataRow(
                  cells: [
                    const DataCell(Text('School-time block')),
                    DataCell(Text(_scheduleWindow(young, ScheduleType.school))),
                    DataCell(
                        Text(_scheduleWindow(middle, ScheduleType.school))),
                    DataCell(Text(_scheduleWindow(teen, ScheduleType.school))),
                  ],
                ),
                DataRow(
                  cells: [
                    const DataCell(Text('Safe search')),
                    DataCell(Text(young.safeSearchEnabled ? 'On' : 'Off')),
                    DataCell(Text(middle.safeSearchEnabled ? 'On' : 'Off')),
                    DataCell(Text(teen.safeSearchEnabled ? 'On' : 'Off')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _scheduleWindow(Policy policy, ScheduleType type) {
    for (final schedule in policy.schedules) {
      if (schedule.type == type) {
        return '${schedule.startTime}-${schedule.endTime}';
      }
    }
    return 'None';
  }

  Widget _buildAgeBandCard(
    BuildContext context, {
    required AgeBand ageBand,
    required String title,
    required String subtitle,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    final policy = Policy.presetForAgeBand(ageBand);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.22)),
      ),
      child: ExpansionTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        collapsedShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(subtitle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          _buildSection(
            context,
            title: 'Blocked Content',
            icon: Icons.block,
            items: policy.blockedCategories
                .map((cat) => _formatCategoryName(cat))
                .toList(),
            color: Colors.red,
          ),
          if (policy.schedules.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildSection(
              context,
              title: 'Time Restrictions',
              icon: Icons.schedule,
              items: policy.schedules
                  .map((s) => '${s.name}: ${s.startTime} - ${s.endTime}')
                  .toList(),
              color: Colors.orange,
            ),
          ],
          if (policy.safeSearchEnabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.search, size: 16, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Text(
                  'Safe search enabled',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why these restrictions?',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  _getAgeRationale(ageBand),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<String> items,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(left: 24, top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade600,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhilosophySection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF172638) : const Color(0xFFEFF7FF);
    final borderColor =
        isDark ? Colors.blue.withValues(alpha: 0.35) : const Color(0xFFBFDBFE);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'Our Philosophy',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.blue.shade900,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Age-appropriate filtering is not about blocking everything. It creates a safe space for exploration while protecting children from content they are not ready for.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _buildPhilosophyPoint(
            context,
            'Gradual freedom as they grow',
            'Restrictions ease as children mature and develop judgment.',
          ),
          const SizedBox(height: 8),
          _buildPhilosophyPoint(
            context,
            'Transparency over surveillance',
            'Children know what is blocked and why.',
          ),
          const SizedBox(height: 8),
          _buildPhilosophyPoint(
            context,
            'Customizable to your values',
            'Every family is different. Adjust presets as needed.',
          ),
        ],
      ),
    );
  }

  Widget _buildPhilosophyPoint(
    BuildContext context,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: Colors.blue.shade700,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatCategoryName(String category) {
    return category
        .split('-')
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  String _getAgeRationale(AgeBand ageBand) {
    switch (ageBand) {
      case AgeBand.young:
        return 'Young children are building digital awareness. Strict filters and earlier bedtime help create a safer foundation.';
      case AgeBand.middle:
        return 'Middle schoolers need balanced protection. They can explore while still being protected from risky content.';
      case AgeBand.teen:
        return 'Teenagers need growing independence. Focus shifts to truly dangerous content while respecting maturity.';
    }
  }
}

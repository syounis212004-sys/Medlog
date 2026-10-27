import 'package:flutter/material.dart';

import 'i18n.dart' show textDirectionFor, isAr;
import 'i18n_ar.dart' show kAr;

/// Icon for each specialty (Material outlined set).
IconData specialtyIcon(String name) {
  switch (name) {
    case 'Internal Medicine':
      return Icons.medical_services_outlined;
    case 'General Surgery':
      return Icons.content_cut;
    case 'Pediatrics':
      return Icons.child_care;
    case 'OB/GYN':
      return Icons.pregnant_woman;
    case 'Emergency':
      return Icons.emergency_outlined;
    case 'ICU':
      return Icons.monitor_heart_outlined;
    case 'Orthopedics':
      return Icons.personal_injury_outlined;
    case 'Family Medicine':
      return Icons.family_restroom;
    case 'Neurology':
      return Icons.psychology_outlined;
    case 'Psychiatry':
      return Icons.self_improvement;
    case 'ENT':
      return Icons.hearing;
    case 'Ophthalmology':
      return Icons.visibility_outlined;
    case 'Dermatology':
      return Icons.back_hand_outlined;
    case 'Urology':
      return Icons.water_drop_outlined;
    case 'Anesthesia':
      return Icons.air;
    case 'Cardiology':
      return Icons.favorite_outline;
    default:
      return Icons.medical_information_outlined;
  }
}

Color specialtyColor(String name) {
  switch (name) {
    case 'Internal Medicine':
      return const Color(0xFF00796B);
    case 'General Surgery':
      return const Color(0xFF5E35B1);
    case 'Pediatrics':
      return const Color(0xFFF9A825);
    case 'OB/GYN':
      return const Color(0xFFD81B60);
    case 'Emergency':
      return const Color(0xFFE53935);
    case 'ICU':
      return const Color(0xFF3949AB);
    case 'Orthopedics':
      return const Color(0xFF6D4C41);
    case 'Family Medicine':
      return const Color(0xFF43A047);
    case 'Neurology':
      return const Color(0xFF8E24AA);
    case 'Psychiatry':
      return const Color(0xFF00ACC1);
    case 'ENT':
      return const Color(0xFFEF6C00);
    case 'Ophthalmology':
      return const Color(0xFF1E88E5);
    case 'Dermatology':
      return const Color(0xFFEC407A);
    case 'Urology':
      return const Color(0xFF039BE5);
    case 'Anesthesia':
      return const Color(0xFF546E7A);
    case 'Cardiology':
      return const Color(0xFFC62828);
    default:
      return const Color(0xFF757575);
  }
}

/// Round avatar with the specialty icon on a soft tint of its color.
class SpecialtyAvatar extends StatelessWidget {
  final String specialty;
  final double size;
  final bool selected;
  const SpecialtyAvatar(this.specialty, {super.key, this.size = 44, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final col = specialtyColor(specialty);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? Theme.of(context).colorScheme.primary : col.withAlpha(36),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(
        selected ? Icons.check : specialtyIcon(specialty),
        size: size * 0.55,
        color: selected ? Theme.of(context).colorScheme.onPrimary : col,
      ),
    );
  }
}

/// Flat rounded card with a thin outline (lighter and faster than elevated cards).
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final Color? color;
  const AppCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(vertical: 4),
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: margin,
      color: color ?? cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: child,
    );
  }
}

/// Case-derived text with mixed English / Arabic: every paragraph (line) takes the
/// direction of its own first letter, so periods, colons and brackets land on the
/// correct side and each line starts at the edge its script reads from.
/// Text is shown as written (never translated).
class DirText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const DirText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final base = Directionality.of(context);
    final paras = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in paras)
          if (p.trim().isEmpty)
            SizedBox(height: (style?.fontSize ?? 14) * 0.6)
          else
            Builder(builder: (_) {
              final d = textDirectionFor(p) ?? base;
              return Directionality(
                textDirection: d,
                child: Text(p, textAlign: TextAlign.start, style: style),
              );
            }),
      ],
    );
  }
}

/// Arabic for workflow and navigation labels (case status, editor tabs, "Next").
/// Unlike tr(), it is not kept in English by the "medical terms in English" switch:
/// those words are interface labels, not clinical terms, and must not mix scripts
/// inside one row.
String trUi(String s) => isAr ? (kAr[s] ?? s) : s;

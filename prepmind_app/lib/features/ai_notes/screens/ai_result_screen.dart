import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/ai_notes_provider.dart';

class AiResultScreen extends ConsumerStatefulWidget {
  final String subjectId;
  final String generationType;
  final String label;

  const AiResultScreen({
    super.key,
    required this.subjectId,
    required this.generationType,
    required this.label,
  });

  @override
  ConsumerState<AiResultScreen> createState() => _AiResultScreenState();
}

class _AiResultScreenState extends ConsumerState<AiResultScreen> {
  @override
  void initState() {
    super.initState();
    // Trigger generation on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(aiNotesProvider((
            subjectId: widget.subjectId,
            generationType: widget.generationType,
          )).notifier)
          .generate();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aiNotesProvider((
      subjectId: widget.subjectId,
      generationType: widget.generationType,
    )));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (state.hasValue && state.value != null)
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.primary),
              tooltip: 'Regenerate',
              onPressed: () {
                ref
                    .read(aiNotesProvider((
                      subjectId: widget.subjectId,
                      generationType: widget.generationType,
                    )).notifier)
                    .generate(forceRegenerate: true);
              },
            ),
        ],
      ),
      body: state.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Generating with AI…',
                  style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 48),
                const SizedBox(height: 12),
                Text(
                  e.toString().replaceAll('Exception: ', ''),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    ref
                        .read(aiNotesProvider((
                          subjectId: widget.subjectId,
                          generationType: widget.generationType,
                        )).notifier)
                        .generate();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (generation) {
          if (generation == null) return const SizedBox.shrink();
          return _ResultRenderer(
            generationType: widget.generationType,
            content: generation.content,
          );
        },
      ),
    );
  }
}

class _ResultRenderer extends StatelessWidget {
  final String generationType;
  final Map<String, dynamic> content;

  const _ResultRenderer({
    required this.generationType,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return switch (generationType) {
      'summary' => _SummaryView(content: content),
      'key_points' => _KeyPointsView(content: content),
      'mcq' => _McqView(content: content),
      'flashcards' => _FlashcardsView(content: content),
      'five_mark_qa' || 'ten_mark_qa' => _QAView(content: content),
      'revision_sheet' => _RevisionSheetView(content: content),
      'mind_map' => _MindMapView(content: content),
      _ => _RawView(content: content),
    };
  }
}

// ─── Summary ─────────────────────────────────────────────────────────────────

class _SummaryView extends StatelessWidget {
  final Map<String, dynamic> content;
  const _SummaryView({required this.content});

  @override
  Widget build(BuildContext context) {
    final sections = (content['sections'] as List?) ?? [];
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: sections.length,
      itemBuilder: (context, i) {
        final section = Map<String, dynamic>.from(sections[i] as Map);
        final points = (section['points'] as List?) ?? [];
        return _SectionCard(
          title: section['title']?.toString() ?? '',
          children:
              points.map((p) => _BulletPoint(text: p.toString())).toList(),
        );
      },
    );
  }
}

// ─── Key Points ──────────────────────────────────────────────────────────────

class _KeyPointsView extends StatelessWidget {
  final Map<String, dynamic> content;
  const _KeyPointsView({required this.content});

  @override
  Widget build(BuildContext context) {
    final points = (content['points'] as List?) ?? [];
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: points.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = Map<String, dynamic>.from(points[i] as Map);
        final importance = p['importance']?.toString() ?? 'medium';
        final color = importance == 'high'
            ? AppColors.error
            : importance == 'low'
                ? AppColors.textSecondary
                : AppColors.primary;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, right: 12),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p['point']?.toString() ?? '',
                        style: const TextStyle(fontSize: 14)),
                    if (p['topic'] != null) ...[
                      const SizedBox(height: 4),
                      Text(p['topic'].toString(),
                          style: TextStyle(
                              fontSize: 11,
                              color: color,
                              fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── MCQ ─────────────────────────────────────────────────────────────────────

class _McqView extends StatefulWidget {
  final Map<String, dynamic> content;
  const _McqView({required this.content});

  @override
  State<_McqView> createState() => _McqViewState();
}

class _McqViewState extends State<_McqView> {
  final Map<int, String?> _selected = {};
  final Map<int, bool> _revealed = {};

  @override
  Widget build(BuildContext context) {
    final questions = (widget.content['questions'] as List?) ?? [];
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: questions.length,
      itemBuilder: (context, i) {
        final q = Map<String, dynamic>.from(questions[i] as Map);
        final options = Map<String, dynamic>.from((q['options'] as Map?) ?? {});
        final correct = q['correct']?.toString();
        final selected = _selected[i];
        final revealed = _revealed[i] ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Q${i + 1}',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  if (q['difficulty'] != null)
                    Text(q['difficulty'].toString(),
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 10),
              Text(q['question']?.toString() ?? '',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 12),
              ...options.entries.map((e) {
                final isCorrect = e.key == correct;
                final isSelected = e.key == selected;
                Color? bg;
                if (revealed) {
                  if (isCorrect) bg = Colors.green.shade50;
                  if (isSelected && !isCorrect)
                    bg = AppColors.error.withOpacity(0.08);
                } else if (isSelected) {
                  bg = AppColors.primaryLight;
                }
                return GestureDetector(
                  onTap: revealed
                      ? null
                      : () => setState(() => _selected[i] = e.key),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bg ?? Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text('${e.key}.',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(e.value.toString(),
                                style: const TextStyle(fontSize: 13))),
                        if (revealed && isCorrect)
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 16),
                        if (revealed && isSelected && !isCorrect)
                          const Icon(Icons.cancel,
                              color: AppColors.error, size: 16),
                      ],
                    ),
                  ),
                );
              }),
              if (selected != null && !revealed)
                TextButton(
                  onPressed: () => setState(() => _revealed[i] = true),
                  child: const Text('Check Answer'),
                ),
              if (revealed && q['explanation'] != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '💡 ${q['explanation']}',
                    style: const TextStyle(fontSize: 13, color: Colors.green),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Flashcards ───────────────────────────────────────────────────────────────

class _FlashcardsView extends StatelessWidget {
  final Map<String, dynamic> content;
  const _FlashcardsView({required this.content});

  @override
  Widget build(BuildContext context) {
    final cards = (content['cards'] as List?) ?? [];
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: cards.length,
      itemBuilder: (context, i) {
        final card = Map<String, dynamic>.from(cards[i] as Map);
        return _FlashCard(
          front: card['front']?.toString() ?? '',
          back: card['back']?.toString() ?? '',
          topic: card['topic']?.toString(),
        );
      },
    );
  }
}

class _FlashCard extends StatefulWidget {
  final String front;
  final String back;
  final String? topic;
  const _FlashCard({required this.front, required this.back, this.topic});

  @override
  State<_FlashCard> createState() => _FlashCardState();
}

class _FlashCardState extends State<_FlashCard> {
  bool _flipped = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _flipped = !_flipped),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _flipped ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _flipped ? AppColors.primary : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _flipped ? 'ANSWER' : 'QUESTION',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _flipped ? Colors.white70 : AppColors.primary,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                if (widget.topic != null)
                  Text(
                    widget.topic!,
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          _flipped ? Colors.white60 : AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _flipped ? widget.back : widget.front,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: _flipped ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Tap to flip',
                style: TextStyle(
                  fontSize: 11,
                  color: _flipped ? Colors.white54 : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Q&A (5-mark / 10-mark) ───────────────────────────────────────────────────

class _QAView extends StatelessWidget {
  final Map<String, dynamic> content;
  const _QAView({required this.content});

  @override
  Widget build(BuildContext context) {
    final questions = (content['questions'] as List?) ?? [];
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: questions.length,
      itemBuilder: (context, i) {
        final q = Map<String, dynamic>.from(questions[i] as Map);
        return _ExpandableQA(
          index: i + 1,
          question: q['question']?.toString() ?? '',
          answer: q['answer']?.toString() ?? '',
          keyPoints:
              (q['key_points'] as List?)?.map((e) => e.toString()).toList() ??
                  [],
        );
      },
    );
  }
}

class _ExpandableQA extends StatefulWidget {
  final int index;
  final String question;
  final String answer;
  final List<String> keyPoints;

  const _ExpandableQA({
    required this.index,
    required this.question,
    required this.answer,
    required this.keyPoints,
  });

  @override
  State<_ExpandableQA> createState() => _ExpandableQAState();
}

class _ExpandableQAState extends State<_ExpandableQA> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Q${widget.index}',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(widget.question,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: Colors.grey.shade200),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(data: widget.answer),
                  if (widget.keyPoints.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Key Points:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.primary)),
                    const SizedBox(height: 6),
                    ...widget.keyPoints.map((p) => _BulletPoint(text: p)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Revision Sheet ───────────────────────────────────────────────────────────

class _RevisionSheetView extends StatelessWidget {
  final Map<String, dynamic> content;
  const _RevisionSheetView({required this.content});

  @override
  Widget build(BuildContext context) {
    final sections = (content['sections'] as List?) ?? [];
    final quickRef = (content['quick_reference'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (quickRef.isNotEmpty) ...[
          _SectionCard(
            title: '⚡ Quick Reference',
            children:
                quickRef.map((q) => _BulletPoint(text: q.toString())).toList(),
          ),
          const SizedBox(height: 12),
        ],
        ...sections.map((s) {
          final section = Map<String, dynamic>.from(s as Map);
          final items = (section['items'] as List?) ?? [];
          return _SectionCard(
            title: section['title']?.toString() ?? '',
            children: items.map((item) {
              final i = Map<String, dynamic>.from(item as Map);
              if (i.containsKey('term')) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i['term']}: ',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      Expanded(
                          child: Text(i['definition']?.toString() ?? '',
                              style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                );
              }
              return _BulletPoint(text: i.values.first?.toString() ?? '');
            }).toList(),
          );
        }),
      ],
    );
  }
}

// ─── Mind Map ─────────────────────────────────────────────────────────────────

class _MindMapView extends StatelessWidget {
  final Map<String, dynamic> content;
  const _MindMapView({required this.content});

  @override
  Widget build(BuildContext context) {
    final branches = (content['branches'] as List?) ?? [];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              content['central_topic']?.toString() ?? '',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ...branches.map((b) {
          final branch = Map<String, dynamic>.from(b as Map);
          final subtopics = (branch['subtopics'] as List?) ?? [];
          Color branchColor;
          try {
            branchColor = Color(
                int.parse((branch['color'] as String).replaceAll('#', '0xFF')));
          } catch (_) {
            branchColor = AppColors.primary;
          }
          return _SectionCard(
            title: branch['topic']?.toString() ?? '',
            color: branchColor,
            children: subtopics.map((sub) {
              final s = Map<String, dynamic>.from(sub as Map);
              final details = (s['details'] as List?) ?? [];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ${s['title']}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    ...details.map((d) => Padding(
                          padding: const EdgeInsets.only(left: 14, top: 2),
                          child: Text('– $d',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        )),
                  ],
                ),
              );
            }).toList(),
          );
        }),
      ],
    );
  }
}

// ─── Raw fallback ─────────────────────────────────────────────────────────────

class _RawView extends StatelessWidget {
  final Map<String, dynamic> content;
  const _RawView({required this.content});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: MarkdownBody(data: content.toString()),
    );
  }
}

// ─── Shared widgets ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Color? color;

  const _SectionCard({
    required this.title,
    required this.children,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: c, width: 3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15, color: c)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _BulletPoint extends StatelessWidget {
  final String text;
  const _BulletPoint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  fontSize: 14)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

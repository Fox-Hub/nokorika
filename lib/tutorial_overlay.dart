// 初回起動時などに使う「画面を暗転させて、特定のウィジェットだけをハイライトし
// "ここをタップ！"と教えるチュートリアル」の汎用パーツ。
//
// 使い方の概要:
//   1. ハイライトしたいウィジェットに GlobalKey を割り当てる。
//   2. 画面の initState 内などで TutorialManager.showIfNeeded() を呼ぶ。
//   3. 一度見せたステップは SharedPreferences に記録され、次回以降は表示されない。
//
// 使用例は main.dart 側のコメントを参照。

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ハイライトの形状
enum TutorialShape { rectangle, circle }

/// チュートリアルの1ステップ分の情報
class TutorialStep {
  /// ハイライトしたい対象ウィジェットに割り当てた GlobalKey
  final GlobalKey targetKey;

  /// 吹き出しに表示する見出し（例: "ここをタップ！"）
  final String title;

  /// 吹き出しに表示する説明文
  final String description;

  /// ハイライトの形（四角 or 丸）
  final TutorialShape shape;

  /// ハイライト範囲に足す余白（対象ウィジェットぴったりだと窮屈な場合に調整）
  final double padding;

  const TutorialStep({
    required this.targetKey,
    required this.title,
    this.description = '',
    this.shape = TutorialShape.rectangle,
    this.padding = 8,
  });
}

/// チュートリアルの表示制御（表示済みフラグの保存/読込 と Overlay 表示）を行うクラス
class TutorialManager {
  TutorialManager._();

  static const String _prefsKeyPrefix = 'tutorial_shown_';

  /// [tutorialId] のチュートリアルが表示済みかどうか
  static Future<bool> isShown(String tutorialId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefsKeyPrefix$tutorialId') ?? false;
  }

  /// 表示済みフラグを立てる
  static Future<void> setShown(String tutorialId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefsKeyPrefix$tutorialId', true);
  }

  /// デバッグ用など、フラグをリセットしたい場合に呼ぶ
  static Future<void> reset(String tutorialId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefsKeyPrefix$tutorialId');
  }

  /// まだ表示していなければチュートリアルを表示する。
  /// 対象ウィジェットの初回描画が終わっている必要があるため、
  /// 呼び出し側では WidgetsBinding.instance.addPostFrameCallback の中から呼ぶこと。
  static Future<void> showIfNeeded({
    required BuildContext context,
    required String tutorialId,
    required List<TutorialStep> steps,
  }) async {
    if (steps.isEmpty) return;
    final alreadyShown = await isShown(tutorialId);
    if (alreadyShown) return;
    if (!context.mounted) return;
    _showOverlay(context: context, tutorialId: tutorialId, steps: steps);
  }

  /// 表示済みでも強制的に再生したいとき（設定画面の「チュートリアルを見る」等）に使う
  static void forceShow({
    required BuildContext context,
    required String tutorialId,
    required List<TutorialStep> steps,
  }) {
    if (steps.isEmpty) return;
    _showOverlay(context: context, tutorialId: tutorialId, steps: steps);
  }

  static void _showOverlay({
    required BuildContext context,
    required String tutorialId,
    required List<TutorialStep> steps,
  }) {
    late OverlayEntry entry;
    final overlay = Overlay.of(context, rootOverlay: true);

    void handleFinished() {
      entry.remove();
      setShown(tutorialId);
    }

    void handleSkip() {
      entry.remove();
      setShown(tutorialId);
    }

    entry = OverlayEntry(
      builder: (overlayContext) {
        return _TutorialOverlayView(
          steps: steps,
          onFinished: handleFinished,
          onSkip: handleSkip,
        );
      },
    );

    overlay.insert(entry);
  }
}

/// 実際に画面全体を覆って表示される、暗転 + スポットライト演出のウィジェット
class _TutorialOverlayView extends StatefulWidget {
  final List<TutorialStep> steps;
  final VoidCallback onFinished;
  final VoidCallback onSkip;

  const _TutorialOverlayView({
    required this.steps,
    required this.onFinished,
    required this.onSkip,
  });

  @override
  State<_TutorialOverlayView> createState() => _TutorialOverlayViewState();
}

class _TutorialOverlayViewState extends State<_TutorialOverlayView>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  late final AnimationController _pulseController;

  TutorialStep get _currentStep => widget.steps[_index];
  bool get _isLastStep => _index == widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_isLastStep) {
      widget.onFinished();
    } else {
      setState(() => _index++);
    }
  }

  /// 対象ウィジェットの画面上の位置とサイズを取得する。
  /// レイアウト前などで取得できない場合は null を返す。
  Rect? _targetRect() {
    final renderObject = _currentStep.targetKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return null;
    final position = renderObject.localToGlobal(Offset.zero);
    return position & renderObject.size;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final rawRect = _targetRect();
    final Rect? highlightRect = rawRect?.inflate(_currentStep.padding);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // 画面全体を覆う暗転 + スポットライトの穴あけ。タップで次のステップへ。
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _goNext,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _SpotlightPainter(
                      highlightRect: highlightRect,
                      shape: _currentStep.shape,
                      pulse: _pulseController.value,
                    ),
                    size: Size.infinite,
                  );
                },
              ),
            ),
          ),

          // ハイライト付近に出す「ここをタップ！」ラベル
          if (highlightRect != null)
            _buildTapLabel(context, highlightRect, screenSize),

          // 説明用の吹き出しカード
          _buildExplanationCard(context, highlightRect, screenSize),

          // 右上のスキップボタン
          Positioned(
            top: topPadding + 8,
            right: 12,
            child: SafeArea(
              child: TextButton(
                onPressed: widget.onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black.withOpacity(0.35),
                ),
                child: const Text('スキップ'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTapLabel(BuildContext context, Rect highlightRect, Size screenSize) {
    // ハイライトの下に十分な余白があれば下に、なければ上に表示する
    final bool labelBelow =
        highlightRect.bottom + 60 < screenSize.height;
    final double top = labelBelow
        ? highlightRect.bottom + 8
        : (highlightRect.top - 44).clamp(0, screenSize.height);

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final scale = 0.95 + (_pulseController.value * 0.1);
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amberAccent,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 8),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  labelBelow ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                  color: Colors.black87,
                ),
                const SizedBox(width: 6),
                Text(
                  _currentStep.title,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExplanationCard(
    BuildContext context,
    Rect? highlightRect,
    Size screenSize,
  ) {
    // ハイライトが無い（対象が見つからない）場合は画面中央に表示する
    final bool centerOnly = highlightRect == null;

    // ハイライトの上半分/下半分どちらに寄っているかでカードの位置を決める
    final bool placeCardAtBottom =
        centerOnly || highlightRect.center.dy < screenSize.height / 2;

    final card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_currentStep.description.isNotEmpty) ...[
            Text(
              _currentStep.description,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_index + 1} / ${widget.steps.length}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              TextButton(
                onPressed: _goNext,
                child: Text(_isLastStep ? 'はじめる' : '次へ'),
              ),
            ],
          ),
        ],
      ),
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: placeCardAtBottom ? 32 : null,
      top: placeCardAtBottom ? null : 32,
      child: SafeArea(child: card),
    );
  }
}

/// 対象範囲だけを切り抜いた暗転オーバーレイを描画する CustomPainter
class _SpotlightPainter extends CustomPainter {
  final Rect? highlightRect;
  final TutorialShape shape;
  final double pulse;

  _SpotlightPainter({
    required this.highlightRect,
    required this.shape,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.75);
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final rect = highlightRect;
    if (rect == null || rect.isEmpty) {
      canvas.drawPath(backgroundPath, overlayPaint);
      return;
    }

    final holePath = shape == TutorialShape.circle
        ? (Path()..addOval(rect))
        : (Path()
            ..addRRect(
              RRect.fromRectAndRadius(rect, const Radius.circular(16)),
            ));

    final combined = Path.combine(
      PathOperation.difference,
      backgroundPath,
      holePath,
    );
    canvas.drawPath(combined, overlayPaint);

    // ハイライト枠を脈打つように描画して視線を誘導する
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.6 + pulse * 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    if (shape == TutorialShape.circle) {
      canvas.drawOval(rect.inflate(pulse * 3), borderPaint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.inflate(pulse * 3),
          const Radius.circular(16),
        ),
        borderPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.highlightRect != highlightRect ||
        oldDelegate.shape != shape ||
        oldDelegate.pulse != pulse;
  }
}

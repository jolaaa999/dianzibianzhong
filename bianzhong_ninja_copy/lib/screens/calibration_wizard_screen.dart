import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_demo_mode.dart';
import '../models/calibration_state.dart';
import '../providers/app_provider.dart';
import '../utils/constants.dart';
import '../utils/stage_hit_mapper.dart';
import '../utils/stage_layout_config.dart';
import '../widgets/stage_bianzhong_view.dart';

/// 系统校准向导（PRD 3.2.6）
class CalibrationWizardScreen extends StatefulWidget {
  const CalibrationWizardScreen({super.key});

  @override
  State<CalibrationWizardScreen> createState() =>
      _CalibrationWizardScreenState();
}

class _CalibrationWizardScreenState extends State<CalibrationWizardScreen> {
  CalibrationState _state = const CalibrationState();
  double _leftOkDuration = 0;
  double _rightOkDuration = 0;
  int? _highlightBellId;
  Timer? _verifyTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AppProvider>();
      if (provider.inputMode != InputMode.vision) {
        provider.connectVisionTracking(provider.visionWsUrl);
      }
      _startStickDetection();
    });
  }

  void _startStickDetection() {
    final provider = context.read<AppProvider>();
    _verifyTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_state.step != CalibrationStep.stickDetection) return;
      _updateStickVerification(provider);
    });
  }

  void _updateStickVerification(AppProvider provider) {
    final frames = provider.stickFramesById;
    final left = frames[1];
    final right = frames[2];

    setState(() {
      if (left != null && left.isVisible && left.confidence > 0.8) {
        _leftOkDuration += 0.1;
        if (_leftOkDuration >= 2.0) {
          _state = _state.copyWith(leftVerified: true);
        }
      } else {
        _leftOkDuration = 0;
      }

      if (right != null && right.isVisible && right.confidence > 0.8) {
        _rightOkDuration += 0.1;
        if (_rightOkDuration >= 2.0) {
          _state = _state.copyWith(rightVerified: true);
        }
      } else {
        _rightOkDuration = 0;
      }
    });
  }

  @override
  void dispose() {
    _verifyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统校准向导'),
        automaticallyImplyLeading: false,
      ),
      body: Stepper(
        currentStep: _state.step.index,
        controlsBuilder: (context, details) => const SizedBox.shrink(),
        steps: [
          Step(
            title: const Text('摄像头画面确认'),
            subtitle: const Text('确认编钟阵列完整出现在画面中'),
            content: _buildCameraStep(),
            isActive: _state.step == CalibrationStep.cameraConfirm,
            state: _state.step.index > 0
                ? StepState.complete
                : StepState.indexed,
          ),
          Step(
            title: const Text('标记球识别测试'),
            subtitle: const Text('依次挥动左右敲击棒'),
            content: _buildStickStep(),
            isActive: _state.step == CalibrationStep.stickDetection,
            state: _state.step.index > 1
                ? StepState.complete
                : (_state.step == CalibrationStep.stickDetection
                    ? StepState.editing
                    : StepState.indexed),
          ),
          Step(
            title: const Text('触发映射验证'),
            subtitle: const Text('敲击对应编钟位置验证映射'),
            content: _buildMappingStep(),
            isActive: _state.step == CalibrationStep.mappingVerify,
            state: _state.isComplete ? StepState.complete : StepState.indexed,
          ),
        ],
      ),
    );
  }

  Widget _buildCameraStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '请确认：\n'
          '• USB 摄像头已连接并正常工作\n'
          '• 编钟展示区域完整出现在画面中\n'
          '• 光照均匀，无强光直射',
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            setState(() {
              _state = _state.copyWith(step: CalibrationStep.stickDetection);
            });
          },
          child: const Text('画面正常，下一步'),
        ),
        TextButton(
          onPressed: () async {
            await context.read<AppProvider>().markCalibrationCompleted();
          },
          child: const Text('跳过校准（调试）'),
        ),
      ],
    );
  }

  Widget _buildStickStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stickStatusRow('左棒 (stick_id=1)', _state.leftVerified, _leftOkDuration),
        const SizedBox(height: 12),
        _stickStatusRow('右棒 (stick_id=2)', _state.rightVerified, _rightOkDuration),
        const SizedBox(height: 8),
        Text(
          '请依次挥动敲击棒，系统需稳定识别 2 秒',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _state.sticksReady
              ? () {
                  setState(() {
                    _state = _state.copyWith(
                      step: CalibrationStep.mappingVerify,
                    );
                    _highlightBellId = BellMapping.getBellId(
                      AppConstants.defaultOctave,
                      StageBellLayout.bells.first.note,
                    );
                  });
                }
              : null,
          child: const Text('两棒均已识别，下一步'),
        ),
      ],
    );
  }

  Widget _stickStatusRow(String label, bool verified, double progress) {
    return Row(
      children: [
        Icon(
          verified ? Icons.check_circle : Icons.radio_button_unchecked,
          color: verified ? Colors.green : Colors.grey,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        if (!verified && progress > 0)
          Text('${progress.toStringAsFixed(1)}s / 2s'),
      ],
    );
  }

  Widget _buildMappingStep() {
    final bellNotes = StageBellLayout.bells.map((b) => b.note).toList();
    final provider = context.watch<AppProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 220,
          child: StageBianzhongView(
            currentOctave: AppConstants.defaultOctave,
            lastStrikeBellId: _highlightBellId,
            activeBellIds: _highlightBellId == null ? const {} : {_highlightBellId!},
            activeHammers: const [],
            hammerSensorStates: const [],
            stickFrames: provider.stickFrames,
            followAlongCurrentBellId: _highlightBellId,
            debugShowHitBoxes: true,
            onBellTapped: (_, __, {StageStrikeRegion region = StageStrikeRegion.center}) {},
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '已验证 ${_state.verifiedBellCount} / ${_state.totalBellsToVerify} 个编钟',
        ),
        if (_highlightBellId != null) ...[
          const SizedBox(height: 12),
          Text(
            '请敲击高亮编钟对应位置',
            style: TextStyle(color: Colors.amber[800], fontWeight: FontWeight.bold),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    final next = _state.verifiedBellCount + 1;
                    _state = _state.copyWith(verifiedBellCount: next);
                    if (next < bellNotes.length) {
                      _highlightBellId = BellMapping.getBellId(
                        AppConstants.defaultOctave,
                        bellNotes[next],
                      );
                    }
                  });
                },
                child: const Text('命中，下一个'),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  final next = _state.verifiedBellCount + 1;
                  _state = _state.copyWith(verifiedBellCount: next);
                });
              },
              child: const Text('跳过'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _state.verifiedBellCount >= _state.totalBellsToVerify ||
                  _state.verifiedBellCount >= 6
              ? () async {
                  await context.read<AppProvider>().markCalibrationCompleted();
                }
              : null,
          child: const Text('完成校准'),
        ),
      ],
    );
  }
}

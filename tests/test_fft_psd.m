%% test_fft_psd - 多频率信号 FFT/PSD 验证脚本
%
% 生成包含 50Hz + 200Hz + 500Hz 的合成信号，验证：
%   1. SignalProcessor.ComputeFFTSingleSided 能否正确识别三个特征频率
%   2. SignalProcessor.ComputeCumulativeRMS 能否正确计算总 RMS
%   3. 导出为标准格式供 SignalAnalysis 导入测试

clear; clc;

% 确保 service 目录在路径中
thisDir = fileparts(mfilename('fullpath'));
addpath(fullfile(thisDir, '..', 'service'));
addpath(fullfile(thisDir, '..', 'model'));

%% 参数
Fs = 2500;           % 采样率 Hz
T  = 2;              % 时长 s
N  = Fs * T;         % 总采样点
t  = (0:N-1)' / Fs;  % 时间向量

%% 生成多频率信号（物理单位：μm）
f1 = 50;   A1 = 10;    % 50 Hz, 10 μm
f2 = 200;  A2 = 5;     % 200 Hz, 5 μm
f3 = 500;  A3 = 2;     % 500 Hz, 2 μm
noise_amp = 0.5;        % 噪声幅值

rng(42);  % 固定随机种子
signal_clean = A1*sin(2*pi*f1*t) + A2*sin(2*pi*f2*t) + A3*sin(2*pi*f3*t);
signal_noisy = signal_clean + noise_amp * randn(N, 1);

%% 1. 测试 FFT
fprintf('========== FFT 测试 ==========\n');
[P1, freq] = SignalProcessor.ComputeFFTSingleSided(signal_noisy, Fs);

% 找前 3 个峰值（排除 DC）
[~, sortIdx] = sort(P1, 'descend');
peakFreqs = freq(sortIdx(1:5));
peakAmps  = P1(sortIdx(1:5));

fprintf('期望频率: 50 Hz (10 μm), 200 Hz (5 μm), 500 Hz (2 μm)\n');
fprintf('检测到的前 5 个峰值:\n');
for i = 1:5
    fprintf('  %.2f Hz  幅值 = %.4f μm\n', peakFreqs(i), peakAmps(i));
end

% 验证：前 3 个峰值应接近期望频率
tol = freq(2) - freq(1) + 0.1;  % 频率分辨率 + 容差
detected = sort(peakFreqs(1:3))';
expected = [50; 200; 500];
pass_fft = all(abs(detected(:) - expected(:)) < tol);
fprintf('\nFFT 频率检测: %s\n', ternary(pass_fft, 'PASS ✓', 'FAIL ✗'));

% 验证：幅值应接近期望值（A/2 因为单边谱归一化）
% 实际幅值取决于窗函数和信号长度，检查相对比例
ratio_50_200 = peakAmps(1) / peakAmps(2);
expected_ratio = A1 / A2;
pass_amp = abs(ratio_50_200 - expected_ratio) < 0.2 && ratio_50_200 > 0;
fprintf('FFT 幅值比例 (50/200): 期望 %.2f, 实际 %.2f → %s\n', ...
    expected_ratio, ratio_50_200, ternary(pass_amp, 'PASS ✓', 'FAIL ✗'));

%% 2. 测试 PSD (累积 RMS)
fprintf('\n========== PSD 测试 ==========\n');
[cumRms, f_psd, totalRms] = SignalProcessor.ComputeCumulativeRMS(signal_noisy, Fs);

% 总 RMS 应接近信号标准差
signal_std = std(signal_noisy);
fprintf('信号标准差: %.6f μm\n', signal_std);
fprintf('PSD 总 RMS: %.6f μm\n', totalRms);
pass_rms = isscalar(totalRms) && abs(totalRms - signal_std) / signal_std < 0.05;  % 5% 容差
fprintf('RMS 一致性: %s (误差 %.2f%%)\n', ...
    ternary(pass_rms, 'PASS ✓', 'FAIL ✗'), ...
    abs(totalRms - signal_std) / signal_std * 100);

%% 3. 可视化
figure('Name', 'FFT/PSD 测试结果', 'Position', [100 100 900 700]);

subplot(3,1,1);
plot(t(1:500), signal_noisy(1:500), 'b', 'LineWidth', 0.8);
xlabel('时间 (s)'); ylabel('幅值 (μm)');
title('时域信号（前 0.2s）'); grid on;

subplot(3,1,2);
semilogx(freq(2:end), P1(2:end), 'b', 'LineWidth', 0.8);
hold on;
% 标记期望频率
for f_exp = [50, 200, 500]
    xline(f_exp, 'r--', sprintf('%d Hz', f_exp), 'LineWidth', 1);
end
xlabel('频率 (Hz)'); ylabel('幅值 (μm)');
title('FFT 单边幅值谱'); grid on;

subplot(3,1,3);
semilogx(f_psd(2:end), cumRms(2:end), 'b', 'LineWidth', 0.8);
xlabel('频率 (Hz)'); ylabel('累积 RMS (μm)');
title(sprintf('累积 RMS（总 RMS = %.4f μm）', totalRms)); grid on;

%% 4. 导出标准格式供 SignalAnalysis 导入
Y1 = signal_noisy;                              % 主信号
Y2 = A1*sin(2*pi*f1*t) + 0.1*randn(N,1);       % 仅 50Hz + 小噪声
Y3 = A2*sin(2*pi*f2*t) + 0.1*randn(N,1);       % 仅 200Hz + 小噪声

data = [Y1, Y2, Y3]; %#ok<NASGU>
outDir = fileparts(mfilename('fullpath'));
outFile = fullfile(outDir, 'test_multifreq_standardized.mat');
save(outFile, 'data');

% 创建 _meta.json
meta = struct();
meta.source_file = '';
meta.source_format = 'mat';
meta.data_hash = '';
meta.source_stats = struct();
meta.import_time = datestr(now, 'yyyy-mm-ddTHH:MM:SS');
meta.row_count = size(data, 1);
meta.column_count = size(data, 2);
meta.sample_rate = Fs;
meta.dataset_name = '';
meta.columns = struct( ...
    'index', {1, 2, 3}, ...
    'name', {'MultiFreq', 'Only50Hz', 'Only200Hz'}, ...
    'unit', {'', '', ''}, ...
    'description', {'', '', ''});
metaPath = strrep(outFile, '.mat', '_meta.json');
fid = fopen(metaPath, 'w');
fprintf(fid, '%s', jsonencode(meta, 'PrettyPrint', true));
fclose(fid);
fprintf('\n已导出: %s\n', outFile);
fprintf('  列: MultiFreq (50+200+500Hz), Only50Hz, Only200Hz\n');
fprintf('  采样率: %d Hz, 时长: %d s, 点数: %d\n', Fs, T, N);
fprintf('在 SignalAnalysis 中导入此文件，设置采样率 = %d Hz 后测试 FFT/PSD\n', Fs);

%% 汇总
fprintf('\n========== 汇总 ==========\n');
allPass = pass_fft && pass_amp && pass_rms;
if allPass
    fprintf('全部测试 PASS ✓\n');
else
    fprintf('存在 FAIL，请检查\n');
end

%% 辅助函数
function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end

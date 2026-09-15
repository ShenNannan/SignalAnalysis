classdef TestSignalProcessor < matlab.unittest.TestCase
% TestSignalProcessor - SignalProcessor 纯函数单测

    methods (Test)
        % ---- ComputeFFTSingleSided ----

        function testComputeFFTSingleSidedFrequency(testCase)
        % 已知正弦波 FFT 峰值频率应等于信号频率
            fs = 1000;
            f0 = 50;
            t = (0:999)' / fs;
            sig = sin(2*pi*f0*t);
            [P1, f] = SignalProcessor.ComputeFFTSingleSided(sig, fs);

            [~, peakIdx] = max(P1);
            testCase.verifyEqual(f(peakIdx), f0, 'AbsTol', 1);
        end

        function testComputeFFTSingleSidedLength(testCase)
        % 输出长度 = floor(N/2) + 1
            fs = 100;
            N = 128;
            sig = randn(N, 1);
            [P1, f] = SignalProcessor.ComputeFFTSingleSided(sig, fs);

            expectedLen = floor(N/2) + 1;
            testCase.verifyEqual(numel(P1), expectedLen);
            testCase.verifyEqual(numel(f), expectedLen);
        end

        function testComputeFFTSingleSidedDetrend(testCase)
        % 直流偏置应被去除（去均值 + detrend）
            fs = 100;
            sig = ones(200, 1) * 5;  % 纯直流
            [P1, ~] = SignalProcessor.ComputeFFTSingleSided(sig, fs);

            % 去均值后直流分量应接近 0
            testCase.verifyEqual(P1(1), 0, 'AbsTol', 1e-10);
        end

        function testComputeFFTSingleSidedFrequencyAxis(testCase)
        % 频率轴范围应为 [0, fs/2]
            fs = 500;
            sig = randn(256, 1);
            [~, f] = SignalProcessor.ComputeFFTSingleSided(sig, fs);

            testCase.verifyEqual(f(1), 0);
            testCase.verifyEqual(f(end), fs/2, 'AbsTol', fs/256);
        end

        % ---- ComputeCumulativeRMS ----

        function testComputeCumulativeRMSMonotonic(testCase)
        % 累积 RMS 应单调递增
            fs = 1000;
            sig = randn(5000, 1);
            [cumRms, ~, ~] = SignalProcessor.ComputeCumulativeRMS(sig, fs);

            testCase.verifyTrue(all(diff(cumRms) >= 0));
        end

        function testComputeCumulativeRMSTotalRms(testCase)
        % totalRms 应等于 cumRms 的终值
            fs = 1000;
            sig = randn(5000, 1);
            [cumRms, ~, totalRms] = SignalProcessor.ComputeCumulativeRMS(sig, fs);

            testCase.verifyEqual(cumRms(end), totalRms, 'AbsTol', 1e-12);
        end

        function testComputeCumulativeRMSKnownSignal(testCase)
        % 已知信号的总 RMS 应接近理论值
            fs = 1000;
            f0 = 100;
            amp = 2;
            t = (0:9999)' / fs;
            sig = amp * sin(2*pi*f0*t);
            [~, ~, totalRms] = SignalProcessor.ComputeCumulativeRMS(sig, fs);

            % 正弦波 RMS = amp / sqrt(2) ≈ 1.414
            expectedRms = amp / sqrt(2);
            testCase.verifyEqual(totalRms, expectedRms, 'AbsTol', 0.1);
        end

        function testComputeCumulativeRMSStartsAtZero(testCase)
        % 累积 RMS 第一个点应为 0（pxx(1) 被置零）
            fs = 1000;
            sig = randn(1000, 1);
            [cumRms, ~, ~] = SignalProcessor.ComputeCumulativeRMS(sig, fs);

            testCase.verifyEqual(cumRms(1), 0, 'AbsTol', 1e-15);
        end
    end
end

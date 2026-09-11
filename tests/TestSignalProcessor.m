classdef TestSignalProcessor < matlab.unittest.TestCase
% TestSignalProcessor - SignalProcessor 单元测试

    methods (Test)
        function TestComputeFFT(testCase)
        % 测试 FFT 计算
            Fs = 1000;
            t = (0:999)' / Fs;
            f1 = 50;  % 50Hz 信号
            signal = sin(2*pi*f1*t);

            result = SignalProcessor.ComputeFFT(signal, 1/Fs);

            % 找到峰值频率
            [~, peakIdx] = max(result.Amplitude);
            testCase.verifyEqual(result.Frequency(peakIdx), f1, 'AbsTol', 2);
        end

        function TestComputePSD(testCase)
        % 测试 PSD 计算
            Fs = 1000;
            t = (0:999)' / Fs;
            f1 = 100;
            signal = sin(2*pi*f1*t);

            result = SignalProcessor.ComputePSD(signal, Fs);

            testCase.verifyTrue(length(result.Power) > 0);
            testCase.verifyTrue(length(result.Frequency) > 0);
            testCase.verifyEqual(length(result.Power), length(result.Frequency));
        end

        function TestDifferentiateSignal(testCase)
        % 测试微分
            signal = [0; 1; 4; 9; 16];  % t^2
            sampleTime = 1;

            dy = SignalProcessor.DifferentiateSignal(signal, sampleTime);

            % d(t^2)/dt = 2t，离散近似
            testCase.verifyEqual(length(dy), 4);
            testCase.verifyEqual(dy(1), 1, 'AbsTol', 0.01);  % (1-0)/1
            testCase.verifyEqual(dy(2), 3, 'AbsTol', 0.01);  % (4-1)/1
        end

        function TestIntegrateSignal(testCase)
        % 测试积分
            signal = [1; 1; 1; 1];  % 常数
            sampleTime = 1;

            y = SignalProcessor.IntegrateSignal(signal, sampleTime);

            % 积分结果应该是 [0; 1; 2; 3]
            testCase.verifyEqual(y(1), 0, 'AbsTol', 0.01);
            testCase.verifyEqual(y(2), 1, 'AbsTol', 0.01);
            testCase.verifyEqual(y(4), 3, 'AbsTol', 0.01);
        end

        function TestComputeMovingStats(testCase)
        % 测试滑动统计
            signal = [1; 2; 3; 4; 5];
            windowSize = 3;

            [m, s] = SignalProcessor.ComputeMovingStats(signal, windowSize);

            testCase.verifyEqual(length(m), 5);
            testCase.verifyEqual(length(s), 5);
            testCase.verifyEqual(m(3), 3, 'AbsTol', 0.01);  % mean(2,3,4)
        end

        function TestApplyLowPass(testCase)
        % 测试低通滤波
            Fs = 1000;
            t = (0:999)' / Fs;
            % 低频 + 高频信号
            signal = sin(2*pi*10*t) + sin(2*pi*200*t);

            filtered = SignalProcessor.ApplyLowPass(signal, 50, 0.7, 1/Fs);

            % 滤波后高频分量应该被衰减
            testCase.verifyEqual(length(filtered), length(signal));
        end

        function TestApplyHighPass(testCase)
        % 测试高通滤波
            Fs = 1000;
            t = (0:999)' / Fs;
            signal = sin(2*pi*10*t) + sin(2*pi*200*t);

            filtered = SignalProcessor.ApplyHighPass(signal, 100, 0.7, 1/Fs);

            testCase.verifyEqual(length(filtered), length(signal));
        end

        function TestApplyNotch(testCase)
        % 测试陷波滤波
            Fs = 1000;
            t = (0:999)' / Fs;
            signal = sin(2*pi*50*t);

            filtered = SignalProcessor.ApplyNotch(signal, 50, 0.01, 50, 0.1, 1/Fs);

            testCase.verifyEqual(length(filtered), length(signal));
        end

        function TestComputeMadsd(testCase)
        % 测试 MADSD
            % 常数信号的微分为0
            signal = ones(100, 1);
            madsd = SignalProcessor.ComputeMadsd(signal, 0.001);
            testCase.verifyEqual(madsd, 0, 'AbsTol', 1e-10);

            % 线性信号的微分为常数
            signal = (0:99)';
            madsd = SignalProcessor.ComputeMadsd(signal, 1);
            testCase.verifyEqual(madsd, 1, 'AbsTol', 1e-10);
        end

        function TestLinearRegression(testCase)
        % 测试线性回归
            x = (1:100)';
            y = 2 * x + 3 + randn(100, 1) * 0.1;

            [slope, intercept] = SignalProcessor.LinearRegression(x, y);

            testCase.verifyEqual(slope, 2, 'AbsTol', 0.1);
            testCase.verifyEqual(intercept, 3, 'AbsTol', 0.5);
        end
    end
end

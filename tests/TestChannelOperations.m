classdef TestChannelOperations < matlab.unittest.TestCase
% TestChannelOperations - ChannelOperations 纯函数单测

    methods (Test)
        function testApplySliceNormal(testCase)
            sig = ChannelOperations.ApplySlice((1:5)', 1, 3);
            testCase.verifyEqual(sig, (1:3)');
        end

        function testApplySliceEndAtLength(testCase)
            sig = ChannelOperations.ApplySlice((1:5)', 2, 5);
            testCase.verifyEqual(sig, (2:5)');
        end

        function testApplySliceRingWrap(testCase)
            sig = ChannelOperations.ApplySlice((1:5)', 4, 7);
            testCase.verifyEqual(sig, [4; 5; 1; 2]);
        end

        function testApplySliceClampStart(testCase)
            sig = ChannelOperations.ApplySlice((1:5)', 9, 7);
            % startRow 钳制到 5，endRow=7 回绕 → [5 1 2]
            testCase.verifyEqual(sig, [5; 1; 2]);
        end

        function testComputeAdd(testCase)
            r = ChannelOperations.Compute('add', (1:2)', (3:4)', struct());
            testCase.verifyEqual(r, [4; 6]);
        end

        function testComputeSub(testCase)
            r = ChannelOperations.Compute('sub', (1:2)', (3:4)', struct());
            testCase.verifyEqual(r, [-2; -2]);
        end

        function testComputeMul(testCase)
            r = ChannelOperations.Compute('mul', (2:3)', (3:4)', struct());
            testCase.verifyEqual(r, [6; 12]);
        end

        function testComputeDivZeroGivesNaN(testCase)
            r = ChannelOperations.Compute('div', [4; 2], [2; 0], struct());
            testCase.verifyEqual(r(1), 2);
            testCase.verifyTrue(isnan(r(2)));
        end

        function testComputeDiff(testCase)
            r = ChannelOperations.Compute('diff', [0; 1; 3], [], struct('sampleRate', 2));
            testCase.verifyEqual(r, [2; 4]);
        end

        function testComputeDiffRequiresSampleRate(testCase)
            testCase.verifyError( ...
                @() ChannelOperations.Compute('diff', [0; 1; 3], [], struct()), ...
                'SignalAnalysis:ChannelOperations:MissingSampleRate');
        end

        function testComputeCumsum(testCase)
            r = ChannelOperations.Compute('cumsum', [1; 2; 3], [], struct('sampleRate', 2));
            testCase.verifyEqual(r, [0.5; 1.5; 3]);
        end

        function testComputeRms(testCase)
            r = ChannelOperations.Compute('rms', [0; 3; 4], [], struct());
            testCase.verifyEqual(r, 5 / sqrt(3), 'AbsTol', 1e-12);
        end

        function testComputeSmooth(testCase)
            r = ChannelOperations.Compute('smooth', (1:5)', [], struct('windowSize', 3));
            testCase.verifyEqual(r, [1.5; 2; 3; 4; 4.5]);
        end

        function testComputeLengthMismatch(testCase)
            testCase.verifyError( ...
                @() ChannelOperations.Compute('add', (1:3)', (1:2)', struct()), ...
                'SignalAnalysis:ChannelOperations:LengthMismatch');
        end

        function testComputeUnknownOp(testCase)
            testCase.verifyError( ...
                @() ChannelOperations.Compute('nope', (1:3)', [], struct()), ...
                'SignalAnalysis:ChannelOperations:UnknownOp');
        end

        function testComputeStatsBasic(testCase)
            stats = ChannelOperations.ComputeStats((1:5)', 2, 4, 1);
            testCase.verifyEqual(stats.minY, 2);
            testCase.verifyEqual(stats.maxY, 4);
            testCase.verifyEqual(stats.meanY, 3);
            testCase.verifyEqual(stats.stdY, 1);
        end

        function testComputeStatsSliceOffset(testCase)
            % sliceStart=3: refStartLocal=max(1,2-3+1)=1, refEndLocal=min(5,4-3+1)=2 → [1 2]
            stats = ChannelOperations.ComputeStats((1:5)', 2, 4, 3);
            testCase.verifyEqual(stats.minY, 1);
            testCase.verifyEqual(stats.maxY, 2);
        end

        function testComputeStatsInvalidWindowFallsBack(testCase)
            % refStartLocal=6 >= refEndLocal=5 → 回退全窗 [1 5]
            stats = ChannelOperations.ComputeStats((1:5)', 6, 7, 1);
            testCase.verifyEqual(stats.minY, 1);
            testCase.verifyEqual(stats.maxY, 5);
        end
    end
end

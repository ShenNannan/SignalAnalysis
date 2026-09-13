classdef TestExtractFrfCurves < matlab.unittest.TestCase
% TestExtractFrfCurves - ExtractFrfCurves 纯函数单测

    methods (Test)
        function testFourColumnSingleCurve(testCase)
            ds = Dataset(repmat((1:10)', 1, 4), {'Amp', 'Phase', 'Corr', 'Freq'}, ...
                [], 'D:/data/test_standardized.mat', 'dsa_frf');
            curves = DataReaderFactory.ExtractFrfCurves(ds);

            testCase.verifyEqual(numel(curves), 1);
            testCase.verifyEqual(curves.name, 'test');
            testCase.verifyEqual(curves.freq, (1:10)');
            testCase.verifyEqual(curves.amp, (1:10)');
            testCase.verifyEqual(curves.phase, (1:10)');
            testCase.verifyEqual(curves.corr, (1:10)');
        end

        function testEightColumnsTwoCurves(testCase)
            m = [(1:8)' (2:9)' (3:10)' (4:11)' (5:12)' (6:13)' (7:14)' (8:15)'];
            ds = Dataset(m, [], [], 'D:/data/multi_standardized.mat', 'dsa_frf');
            curves = DataReaderFactory.ExtractFrfCurves(ds);

            testCase.verifyEqual(numel(curves), 2);
            testCase.verifyEqual(curves(1).name, 'multi#1');
            testCase.verifyEqual(curves(2).name, 'multi#2');
            testCase.verifyEqual(curves(1).amp, (1:8)');
            testCase.verifyEqual(curves(1).phase, (2:9)');
            testCase.verifyEqual(curves(1).corr, (3:10)');
            testCase.verifyEqual(curves(1).freq, (4:11)');
            testCase.verifyEqual(curves(2).amp, (5:12)');
            testCase.verifyEqual(curves(2).freq, (8:15)');
        end

        function testSharedFreqLayout(testCase)
            % 7 列 = 第 1 列共享 Freq + 2 组 [amp, phase, corr]
            ds = Dataset(repmat((1:10)', 1, 7), [], [], 'D:/data/shared_standardized.mat', 'dsa_frf');
            curves = DataReaderFactory.ExtractFrfCurves(ds);

            testCase.verifyEqual(numel(curves), 2);
            testCase.verifyEqual(curves(1).freq, (1:10)');
            testCase.verifyEqual(curves(2).freq, (1:10)');
            testCase.verifyEqual(curves(2).amp, (1:10)');
            testCase.verifyEqual(curves(2).phase, (1:10)');
            testCase.verifyEqual(curves(2).corr, (1:10)');
        end

        function testInvalidLayoutThrows(testCase)
            ds = Dataset(repmat((1:10)', 1, 5), [], [], 'D:/data/bad_standardized.mat', 'dsa_frf');
            testCase.verifyError( ...
                @() DataReaderFactory.ExtractFrfCurves(ds), ...
                'SignalAnalysis:DataReaderFactory:InvalidFrfLayout');
        end

        function testDsaSampleFile(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            sampleDir = fullfile(root, 'DRFDOT', 'DSA_Data');
            testCase.assumeTrue(exist(sampleDir, 'dir') == 7, '样例目录不存在，跳过');

            files = DataReaderFactory.DiscoverDirectory(sampleDir, {'.dat'});
            testCase.assumeNotEmpty(files, '样例目录无 .dat 文件');

            f = files{1};
            [data, ~, tag] = DataReaderFactory.ReadDataMatrix(f.path);
            testCase.verifyEqual(tag, 'dsa_frf');

            ds = Dataset(data, [], [], f.path, tag);
            curves = DataReaderFactory.ExtractFrfCurves(ds);
            testCase.verifyEqual(numel(curves), 1);
            testCase.verifyEqual(length(curves.freq), size(data, 1));
            testCase.verifyEqual(curves.freq(1), 0);
            testCase.verifyTrue(all(curves.corr >= 0 & curves.corr <= 1));
        end
    end
end

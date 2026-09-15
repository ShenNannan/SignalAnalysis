classdef TestDataset < matlab.unittest.TestCase
% TestDataset - Dataset 数据容器单测

    methods (Test)
        % ---- 构造 ----

        function testConstructorBasic(testCase)
            ds = Dataset((1:10)', {'A', 'B'}, 100, '', '', struct());
            testCase.verifyEqual(ds.RowCount, 10);
            testCase.verifyEqual(ds.ColumnCount, 2);
            testCase.verifyEqual(ds.SampleRate, 100);
        end

        function testConstructorAutoColumnNames(testCase)
            ds = Dataset((1:10)', [], [], '', '', struct());
            testCase.verifyEqual(ds.ColumnNames, {'Channel_1'});
        end

        function testConstructorDefaultSampleRate(testCase)
            ds = Dataset((1:10)', {'A'}, [], '', '', struct());
            testCase.verifyTrue(isempty(ds.SampleRate));
            testCase.verifyTrue(isempty(ds.SampleTime));
        end

        function testConstructorValidation(testCase)
            % 列名数量不匹配应报错
            testCase.verifyError( ...
                @() Dataset((1:10)', {'A', 'B', 'C'}, [], '', '', struct()), ...
                'SignalAnalysis:Dataset:InvalidColumnNames');
        end

        % ---- 数据访问 ----

        function testGetColumn(testCase)
            ds = Dataset([1 2; 3 4; 5 6], {'X', 'Y'}, [], '', '', struct());
            testCase.verifyEqual(ds.GetColumn(1), [1; 3; 5]);
            testCase.verifyEqual(ds.GetColumn(2), [2; 4; 6]);
        end

        function testGetColumnOutOfRange(testCase)
            ds = Dataset((1:5)', {'A'}, [], '', '', struct());
            testCase.verifyError( ...
                @() ds.GetColumn(2), ...
                'SignalAnalysis:Dataset:IndexOutOfBounds');
        end

        function testGetColumnName(testCase)
            ds = Dataset((1:5)', {'MyCol'}, [], '', '', struct());
            testCase.verifyEqual(ds.GetColumnName(1), 'MyCol');
        end

        function testGetDisplayLabel(testCase)
            ds = Dataset((1:5)', {'A'}, [], '', struct(), struct());
            % 无描述无单位 → 列名
            testCase.verifyEqual(ds.GetDisplayLabel(1), 'A');
        end

        % ---- 重建 ----

        function testRebuildWithSampleRate(testCase)
            ds = Dataset((1:5)', {'A'}, 100, '', '', struct());
            ds2 = ds.RebuildWithSampleRate(200);
            testCase.verifyEqual(ds2.SampleRate, 200);
            testCase.verifyEqual(ds2.Values, (1:5)');
        end

        function testRebuildWithColumnNames(testCase)
            ds = Dataset((1:5)', {'A'}, 100, '', '', struct());
            ds2 = ds.RebuildWithColumnNames({'B'});
            testCase.verifyEqual(ds2.GetColumnName(1), 'B');
            testCase.verifyEqual(ds2.SampleRate, 100);
        end

        % ---- 子集 ----

        function testGetColumnRange(testCase)
            ds = Dataset([1 2 3; 4 5 6], {'A', 'B', 'C'}, 100, '', '', struct());
            sub = ds.GetColumnRange([1, 3]);
            testCase.verifyEqual(sub.ColumnCount, 2);
            testCase.verifyEqual(sub.GetColumnName(1), 'A');
            testCase.verifyEqual(sub.GetColumnName(2), 'C');
        end

        function testGetRowRange(testCase)
            ds = Dataset((1:10)', {'A'}, 100, '', '', struct());
            sub = ds.GetRowRange(3, 7);
            testCase.verifyEqual(sub.RowCount, 5);
            testCase.verifyEqual(sub.Values, (3:7)');
        end

        % ---- Dependent 属性 ----

        function testTimeVector(testCase)
            ds = Dataset((1:4)', {'A'}, 10, '', '', struct());
            testCase.verifyEqual(ds.TimeVector, [0; 0.1; 0.2; 0.3], 'AbsTol', 1e-12);
        end

        function testDuration(testCase)
            ds = Dataset((1:4)', {'A'}, 10, '', '', struct());
            testCase.verifyEqual(ds.Duration, 0.4, 'AbsTol', 1e-12);
        end

        function testDurationEmptyWhenNoSampleRate(testCase)
            ds = Dataset((1:4)', {'A'}, [], '', '', struct());
            testCase.verifyTrue(isempty(ds.Duration));
        end
    end
end

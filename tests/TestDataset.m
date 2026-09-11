classdef TestDataset < matlab.unittest.TestCase
% TestDataset - Dataset 单元测试

    methods (Test)
        function TestBasicConstruction(testCase)
        % 测试基本构造
            data = rand(100, 3);
            ds = Dataset(data, {'A', 'B', 'C'}, 1000, 'test.dat', 'test');

            testCase.verifyEqual(ds.RowCount, 100);
            testCase.verifyEqual(ds.ColumnCount, 3);
            testCase.verifyEqual(ds.SampleRate, 1000);
            testCase.verifyEqual(ds.SampleTime, 0.001);
            testCase.verifyEqual(ds.ColumnNames, {'A', 'B', 'C'});
        end

        function TestDefaultColumnNames(testCase)
        % 测试自动生成列名
            data = rand(50, 2);
            ds = Dataset(data, [], 100);

            testCase.verifyEqual(ds.ColumnNames, {'Channel_1', 'Channel_2'});
        end

        function TestDefaultSampleRate(testCase)
        % 测试默认采样率
            data = rand(50, 2);
            ds = Dataset(data, {'X', 'Y'}, []);

            testCase.verifyEqual(ds.SampleRate, 1);
            testCase.verifyEqual(ds.SampleTime, 1);
        end

        function TestTimeVector(testCase)
        % 测试时间轴
            data = rand(10, 1);
            ds = Dataset(data, {'Ch1'}, 100);

            t = ds.TimeVector;
            testCase.verifyEqual(length(t), 10);
            testCase.verifyEqual(t(1), 0);
            testCase.verifyEqual(t(2), 0.01, 'AbsTol', 1e-10);
        end

        function TestGetColumn(testCase)
        % 测试获取列
            data = [1 2 3; 4 5 6];
            ds = Dataset(data, {'A', 'B', 'C'}, 100);

            testCase.verifyEqual(ds.GetColumn(1), [1; 4]);
            testCase.verifyEqual(ds.GetColumn(2), [2; 5]);
            testCase.verifyEqual(ds.GetColumn(3), [3; 6]);
        end

        function TestGetColumnName(testCase)
        % 测试获取列名
            data = rand(10, 2);
            ds = Dataset(data, {'X', 'Y'}, 100);

            testCase.verifyEqual(ds.GetColumnName(1), 'X');
            testCase.verifyEqual(ds.GetColumnName(2), 'Y');
        end

        function TestGetDisplayLabel(testCase)
        % 测试智能标签
            data = rand(10, 3);
            ds = Dataset(data, {'A', 'B', 'C'}, 100, '', '', struct(), ...
                {'rad', '', 'Nm'}, {'角度', '', '力矩'});

            testCase.verifyEqual(ds.GetDisplayLabel(1), '角度 (rad)');
            testCase.verifyEqual(ds.GetDisplayLabel(2), 'B');
            testCase.verifyEqual(ds.GetDisplayLabel(3), '力矩 (Nm)');
        end

        function TestGetColumnRange(testCase)
        % 测试列切片
            data = [1 2 3; 4 5 6; 7 8 9];
            ds = Dataset(data, {'A', 'B', 'C'}, 100);

            sub = ds.GetColumnRange([1, 3]);
            testCase.verifyEqual(sub.ColumnCount, 2);
            testCase.verifyEqual(sub.ColumnNames, {'A', 'C'});
            testCase.verifyEqual(sub.Values, [1 3; 4 6; 7 9]);
        end

        function TestGetRowRange(testCase)
        % 测试行切片
            data = [1 2; 3 4; 5 6; 7 8];
            ds = Dataset(data, {'A', 'B'}, 100);

            sub = ds.GetRowRange(2, 3);
            testCase.verifyEqual(sub.RowCount, 2);
            testCase.verifyEqual(sub.Values, [3 4; 5 6]);
        end

        function TestRebuildWithSampleRate(testCase)
        % 测试重建采样率
            data = rand(10, 2);
            ds = Dataset(data, {'A', 'B'}, 100);

            ds2 = ds.RebuildWithSampleRate(200);
            testCase.verifyEqual(ds2.SampleRate, 200);
            testCase.verifyEqual(ds.SampleRate, 100);  % 原始不变
        end

        function TestRebuildWithColumnNames(testCase)
        % 测试重建列名
            data = rand(10, 2);
            ds = Dataset(data, {'A', 'B'}, 100);

            ds2 = ds.RebuildWithColumnNames({'X', 'Y'});
            testCase.verifyEqual(ds2.ColumnNames, {'X', 'Y'});
            testCase.verifyEqual(ds.ColumnNames, {'A', 'B'});  % 原始不变
        end

        function TestInvalidColumnNames(testCase)
        % 测试无效列名
            data = rand(10, 3);
            testCase.verifyError(@() Dataset(data, {'A', 'B'}, 100), ...
                'SignalAnalysis:Dataset:InvalidColumnNames');
        end

        function TestGetColumnOutOfBounds(testCase)
        % 测试越界访问
            data = rand(10, 2);
            ds = Dataset(data, {'A', 'B'}, 100);

            testCase.verifyError(@() ds.GetColumn(3), ...
                'SignalAnalysis:Dataset:IndexOutOfBounds');
        end
    end
end

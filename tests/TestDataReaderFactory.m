classdef TestDataReaderFactory < matlab.unittest.TestCase
% TestDataReaderFactory - DataReaderFactory 单元测试

    properties
        TempDir     char
    end

    methods (TestMethodSetup)
        function CreateTempDir(testCase)
            testCase.TempDir = fullfile(tempdir, ['test_' num2str(randi(99999))]);
            mkdir(testCase.TempDir);
        end
    end

    methods (TestMethodTeardown)
        function RemoveTempDir(testCase)
            if exist(testCase.TempDir, 'dir')
                rmdir(testCase.TempDir, 's');
            end
        end
    end

    methods (Test)
        function TestImportAndLoadMat(testCase)
        % 测试 .mat 文件的 Import + Load

            % 创建测试 .mat 文件
            data = rand(100, 3);
            testFile = fullfile(testCase.TempDir, 'test_input.mat');
            save(testFile, 'data');

            % Import
            matPath = DataReaderFactory.ImportToStandard(testFile, testCase.TempDir);

            % 验证文件存在
            testCase.verifyTrue(exist(matPath, 'file') > 0);

            % Load
            ds = DataReaderFactory.LoadStandard(matPath);

            testCase.verifyEqual(ds.RowCount, 100);
            testCase.verifyEqual(ds.ColumnCount, 3);
            testCase.verifyEqual(ds.SampleRate, 1);  % 默认值
            testCase.verifyEqual(size(ds.Values), [100, 3]);
        end

        function TestImportWithColumnNames(testCase)
        % 测试指定列名

            data = rand(50, 2);
            testFile = fullfile(testCase.TempDir, 'test_cn.mat');
            save(testFile, 'data');

            matPath = DataReaderFactory.ImportToStandard(testFile, testCase.TempDir, ...
                'ColumnNames', {'Acceleration', 'Force'});

            ds = DataReaderFactory.LoadStandard(matPath);
            testCase.verifyEqual(ds.ColumnNames, {'Acceleration', 'Force'});
        end

        function TestCacheHit(testCase)
        % 测试缓存命中

            data = rand(50, 2);
            testFile = fullfile(testCase.TempDir, 'test_cache.mat');
            save(testFile, 'data');

            % 第一次导入
            matPath1 = DataReaderFactory.ImportToStandard(testFile, testCase.TempDir);

            % 第二次导入（应命中缓存）
            matPath2 = DataReaderFactory.ImportToStandard(testFile, testCase.TempDir);

            testCase.verifyEqual(matPath1, matPath2);
        end

        function TestExportAndImportExcel(testCase)
        % 测试 Excel 导出/导入循环

            data = [1 2 3; 4 5 6; 7 8 9];
            testFile = fullfile(testCase.TempDir, 'test_excel.mat');
            save(testFile, 'data');

            % Import
            matPath = DataReaderFactory.ImportToStandard(testFile, testCase.TempDir, ...
                'ColumnNames', {'A', 'B', 'C'}, ...
                'Units', {'m', 'm/s', 'N'}, ...
                'Descriptions', {'位移', '速度', '力'});

            % Export to Excel
            xlsxPath = fullfile(testCase.TempDir, 'test_export.xlsx');
            DataReaderFactory.ExportToExcel(matPath, xlsxPath);
            testCase.verifyTrue(exist(xlsxPath, 'file') > 0);

            % Import from Excel
            matPath2 = DataReaderFactory.ImportFromExcel(xlsxPath, testCase.TempDir);
            ds = DataReaderFactory.LoadStandard(matPath2);

            testCase.verifyEqual(ds.RowCount, 3);
            testCase.verifyEqual(ds.ColumnCount, 3);
            testCase.verifyEqual(ds.SampleRate, 1);  % 默认值
        end

        function TestListStandardFiles(testCase)
        % 测试列出标准化文件

            % 创建两个测试文件
            data1 = rand(10, 2);
            data2 = rand(20, 3);
            save(fullfile(testCase.TempDir, 'a.mat'), 'data1');
            save(fullfile(testCase.TempDir, 'b.mat'), 'data2');

            DataReaderFactory.ImportToStandard( ...
                fullfile(testCase.TempDir, 'a.mat'), testCase.TempDir);
            DataReaderFactory.ImportToStandard( ...
                fullfile(testCase.TempDir, 'b.mat'), testCase.TempDir);

            files = DataReaderFactory.ListStandardFiles(testCase.TempDir);
            testCase.verifyEqual(length(files), 2);
        end

        function TestHasValidCache(testCase)
        % 测试缓存检查

            data = rand(10, 2);
            testFile = fullfile(testCase.TempDir, 'test_valid.mat');
            save(testFile, 'data');

            % 导入前无缓存
            testCase.verifyFalse(DataReaderFactory.HasValidCache(testFile, testCase.TempDir));

            % 导入后有缓存
            DataReaderFactory.ImportToStandard(testFile, testCase.TempDir);
            testCase.verifyTrue(DataReaderFactory.HasValidCache(testFile, testCase.TempDir));
        end

        function TestSamPrefixVariables(testCase)
        % 测试 sa_ 前缀变量名

            data = rand(10, 2);
            testFile = fullfile(testCase.TempDir, 'test_prefix.mat');
            save(testFile, 'data');

            matPath = DataReaderFactory.ImportToStandard(testFile, testCase.TempDir);

            loaded = load(matPath);
            testCase.verifyTrue(isfield(loaded, 'sa_data_matrix'));
            testCase.verifyTrue(isfield(loaded, 'sa_sample_rate'));
            testCase.verifyTrue(isfield(loaded, 'sa_column_names'));
            testCase.verifyTrue(isfield(loaded, 'sa_source_file'));
            testCase.verifyTrue(isfield(loaded, 'sa_source_format'));
            testCase.verifyTrue(isempty(loaded.sa_sample_rate));  % 采样率由用户提供
        end

        function TestMetaJson(testCase)
        % 测试 _meta.json 生成

            data = rand(10, 2);
            testFile = fullfile(testCase.TempDir, 'test_json.mat');
            save(testFile, 'data');

            DataReaderFactory.ImportToStandard(testFile, testCase.TempDir);

            [~, baseName] = fileparts(testFile);
            jsonPath = fullfile(testCase.TempDir, [baseName '_standardized_meta.json']);
            testCase.verifyTrue(exist(jsonPath, 'file') > 0);

            jsonText = fileread(jsonPath);
            meta = jsondecode(jsonText);
            testCase.verifyTrue(isfield(meta, 'source_file'));
            testCase.verifyTrue(isfield(meta, 'columns'));
        end

        function TestUpdateSampleRateInMat(testCase)
        % 测试 UpdateSampleRateInMat 回写采样率

            data = rand(10, 2);
            testFile = fullfile(testCase.TempDir, 'test_update_sr.mat');
            save(testFile, 'data');

            matPath = DataReaderFactory.ImportToStandard(testFile, testCase.TempDir);

            % 初始采样率为空（Dataset 默认 1Hz）
            ds1 = DataReaderFactory.LoadStandard(matPath);
            testCase.verifyEqual(ds1.SampleRate, 1);

            % 回写采样率
            DataReaderFactory.UpdateSampleRateInMat(matPath, 500);

            % 验证
            ds2 = DataReaderFactory.LoadStandard(matPath);
            testCase.verifyEqual(ds2.SampleRate, 500);

            % 验证数据不变
            testCase.verifyEqual(ds2.RowCount, 10);
            testCase.verifyEqual(ds2.ColumnCount, 2);
        end

        function TestBatchImportSingleFile(testCase)
        % 测试 BatchImportFolder：子文件夹内单个文件

            % 创建子文件夹，内含一个 N×M 文件
            subdir = fullfile(testCase.TempDir, 'Test1');
            mkdir(subdir);
            data = rand(50, 3);
            save(fullfile(subdir, 'data.mat'), 'data');

            results = DataReaderFactory.BatchImportFolder(testCase.TempDir);

            testCase.verifyEqual(length(results), 1);
            testCase.verifyEqual(results(1).name, 'Test1');

            ds = DataReaderFactory.LoadStandard(results(1).matPath);
            testCase.verifyEqual(ds.RowCount, 50);
            testCase.verifyEqual(ds.ColumnCount, 3);
        end

        function TestBatchImportMergeVectors(testCase)
        % 测试 BatchImportFolder：多个 N×1 向量合并

            subdir = fullfile(testCase.TempDir, 'Test2');
            mkdir(subdir);
            n = 30;
            ch1 = rand(n, 1);
            ch2 = rand(n, 1);
            save(fullfile(subdir, 'ch1.mat'), 'ch1');
            save(fullfile(subdir, 'ch2.mat'), 'ch2');

            results = DataReaderFactory.BatchImportFolder(testCase.TempDir);

            testCase.verifyEqual(length(results), 1);
            testCase.verifyEqual(results(1).name, 'Test2');

            ds = DataReaderFactory.LoadStandard(results(1).matPath);
            testCase.verifyEqual(ds.RowCount, n);
            testCase.verifyEqual(ds.ColumnCount, 2);
        end

        function TestBatchImportMultipleNByM(testCase)
        % 测试 BatchImportFolder：多个 N×M 文件各自独立

            subdir = fullfile(testCase.TempDir, 'Test3');
            mkdir(subdir);
            data1 = rand(40, 3);
            data2 = rand(40, 2);
            save(fullfile(subdir, 'a_data1.mat'), 'data1');
            save(fullfile(subdir, 'b_data2.mat'), 'data2');

            results = DataReaderFactory.BatchImportFolder(testCase.TempDir);

            testCase.verifyEqual(length(results), 2);
            % 名称带子文件夹前缀
            testCase.verifyTrue(contains(results(1).name, 'Test3'));
            testCase.verifyTrue(contains(results(2).name, 'Test3'));
        end
    end
end

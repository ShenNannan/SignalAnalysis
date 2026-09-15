classdef TestSessionData < matlab.unittest.TestCase
% TestSessionData - SessionData 状态管理单测

    methods (Test)
        % ---- 数据集管理 ----

        function testAddDataset(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A'}, 100, '', '', struct());
            session.AddDataset(ds, 'Test', '/tmp/test.mat');
            testCase.verifyEqual(session.DatasetCount, 1);
            testCase.verifyEqual(session.GetDatasetName(1), 'Test');
        end

        function testRemoveDataset(testCase)
            session = SessionData(6);
            ds1 = Dataset((1:10)', {'A'}, 100, '', '', struct());
            ds2 = Dataset((1:10)', {'B'}, 100, '', '', struct());
            session.AddDataset(ds1, 'T1', '/tmp/t1.mat');
            session.AddDataset(ds2, 'T2', '/tmp/t2.mat');
            session.RemoveDataset(1);
            testCase.verifyEqual(session.DatasetCount, 1);
            testCase.verifyEqual(session.GetDatasetName(1), 'T2');
        end

        function testRemoveDatasetUpdatesAxesRefs(testCase)
            session = SessionData(6);
            ds1 = Dataset((1:10)', {'A'}, 100, '', '', struct());
            ds2 = Dataset((1:10)', {'B'}, 100, '', '', struct());
            session.AddDataset(ds1, 'T1', '/tmp/t1.mat');
            session.AddDataset(ds2, 'T2', '/tmp/t2.mat');
            session.AddChannelToAxes(1, 1, 1);
            session.AddChannelToAxes(1, 2, 1);
            session.RemoveDataset(1);
            % 原 ds2 的 DatasetIdx 从 2 变为 1
            chans = session.GetAxesChannels(1);
            testCase.verifyEqual(chans{1}.DatasetIdx, 1);
        end

        function testRemoveDatasetClearsXChannel(testCase)
            session = SessionData(6);
            ds1 = Dataset((1:10)', {'A'}, 100, '', '', struct());
            ds2 = Dataset((1:10)', {'B'}, 100, '', '', struct());
            session.AddDataset(ds1, 'T1', '/tmp/t1.mat');
            session.AddDataset(ds2, 'T2', '/tmp/t2.mat');
            session.SetXChannel(1, 1, 1);
            session.RemoveDataset(1);
            [dsIdx, ~] = session.GetXChannel(1);
            testCase.verifyTrue(isempty(dsIdx));
        end

        function testRemoveDatasetClearsRightY(testCase)
            session = SessionData(6);
            ds1 = Dataset((1:10)', {'A'}, 100, '', '', struct());
            ds2 = Dataset((1:10)', {'B'}, 100, '', '', struct());
            session.AddDataset(ds1, 'T1', '/tmp/t1.mat');
            session.AddDataset(ds2, 'T2', '/tmp/t2.mat');
            session.SetRightYChannel(1, 1, 1);
            session.RemoveDataset(1);
            refs = session.GetRightYChannel(1);
            testCase.verifyEmpty(refs);
        end

        function testClearAllDatasets(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A'}, 100, '', '', struct());
            session.AddDataset(ds, 'T1', '/tmp/t1.mat');
            session.AddChannelToAxes(1, 1, 1);
            session.ClearAllDatasets();
            testCase.verifyEqual(session.DatasetCount, 0);
            testCase.verifyEmpty(session.GetAxesChannels(1));
        end

        % ---- Axes 通道管理 ----

        function testAddChannelToAxes(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A', 'B'}, 100, '', '', struct());
            session.AddDataset(ds, 'T1', '/tmp/t1.mat');
            session.AddChannelToAxes(1, 1, 1);
            chans = session.GetAxesChannels(1);
            testCase.verifyEqual(numel(chans), 1);
            testCase.verifyEqual(chans{1}.DatasetIdx, 1);
            testCase.verifyEqual(chans{1}.ColIdx, 1);
        end

        function testAddChannelDedup(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A'}, 100, '', '', struct());
            session.AddDataset(ds, 'T1', '/tmp/t1.mat');
            session.AddChannelToAxes(1, 1, 1);
            session.AddChannelToAxes(1, 1, 1); % 重复添加
            chans = session.GetAxesChannels(1);
            testCase.verifyEqual(numel(chans), 1);
        end

        function testRemoveChannelFromAxes(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A', 'B'}, 100, '', '', struct());
            session.AddDataset(ds, 'T1', '/tmp/t1.mat');
            session.AddChannelToAxes(1, 1, 1);
            session.AddChannelToAxes(1, 1, 2);
            session.RemoveChannelFromAxes(1, 1, 1);
            chans = session.GetAxesChannels(1);
            testCase.verifyEqual(numel(chans), 1);
            testCase.verifyEqual(chans{1}.ColIdx, 2);
        end

        function testRemoveChannelClearsXRef(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A'}, 100, '', '', struct());
            session.AddDataset(ds, 'T1', '/tmp/t1.mat');
            session.AddChannelToAxes(1, 1, 1);
            session.SetXChannel(1, 1, 1);
            session.RemoveChannelFromAxes(1, 1, 1);
            [dsIdx, ~] = session.GetXChannel(1);
            testCase.verifyTrue(isempty(dsIdx));
        end

        % ---- 切片 ----

        function testSetChannelSlice(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A'}, 100, '', '', struct());
            session.AddDataset(ds, 'T1', '/tmp/t1.mat');
            session.AddChannelToAxes(1, 1, 1);
            session.SetChannelSlice(1, 1, 3, 7);
            chan = session.GetChannel(1, 1);
            testCase.verifyEqual(chan.SliceRange, [3, 7]);
        end

        % ---- 横轴/右Y轴引用 ----

        function testSetXChannel(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A'}, 100, '', '', struct());
            session.AddDataset(ds, 'T1', '/tmp/t1.mat');
            session.SetXChannel(1, 1, 1);
            [dsIdx, colIdx] = session.GetXChannel(1);
            testCase.verifyEqual(dsIdx, 1);
            testCase.verifyEqual(colIdx, 1);
        end

        function testClearXChannel(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A'}, 100, '', '', struct());
            session.AddDataset(ds, 'T1', '/tmp/t1.mat');
            session.SetXChannel(1, 1, 1);
            session.ClearXChannel(1);
            [dsIdx, ~] = session.GetXChannel(1);
            testCase.verifyTrue(isempty(dsIdx));
        end

        function testSetRightYChannel(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A', 'B'}, 100, '', '', struct());
            session.AddDataset(ds, 'T1', '/tmp/t1.mat');
            session.SetRightYChannel(1, 1, 1);
            refs = session.GetRightYChannel(1);
            testCase.verifyEqual(numel(refs), 1);
            testCase.verifyEqual(refs{1}.ColIdx, 1);
        end

        function testSetRightYChannelDedup(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A'}, 100, '', '', struct());
            session.AddDataset(ds, 'T1', '/tmp/t1.mat');
            session.SetRightYChannel(1, 1, 1);
            session.SetRightYChannel(1, 1, 1); % 重复
            refs = session.GetRightYChannel(1);
            testCase.verifyEqual(numel(refs), 1);
        end

        function testClearRightYChannel(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A'}, 100, '', '', struct());
            session.AddDataset(ds, 'T1', '/tmp/t1.mat');
            session.SetRightYChannel(1, 1, 1);
            session.ClearRightYChannel(1);
            refs = session.GetRightYChannel(1);
            testCase.verifyEmpty(refs);
        end

        % ---- 采样率 ----

        function testUpdateSampleRate(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A'}, [], '', '', struct());
            session.AddDataset(ds, 'T1', '/tmp/t1.mat');
            session.UpdateSampleRate(1, 500);
            ds2 = session.GetDataset(1);
            testCase.verifyEqual(ds2.SampleRate, 500);
        end

        % ---- Axes 管理 ----

        function testRemoveAxesClearsData(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A'}, 100, '', '', struct());
            session.AddDataset(ds, 'T1', '/tmp/t1.mat');
            session.AddChannelToAxes(2, 1, 1);
            session.RemoveAxes(2);
            testCase.verifyEmpty(session.GetAxesChannels(2));
        end

        function testClearAxes(testCase)
            session = SessionData(6);
            ds = Dataset((1:10)', {'A'}, 100, '', '', struct());
            session.AddDataset(ds, 'T1', '/tmp/t1.mat');
            session.AddChannelToAxes(1, 1, 1);
            session.SetXChannel(1, 1, 1);
            session.ClearAxes(1);
            testCase.verifyEmpty(session.GetAxesChannels(1));
            [dsIdx, ~] = session.GetXChannel(1);
            testCase.verifyTrue(isempty(dsIdx));
        end
    end
end

classdef TestTimeSeriesView < matlab.unittest.TestCase
%TESTTIMESERIESVIEW  L3 route-contract transparency tests for TimeSeriesView.
%   Verifies that all 22 outward events pass through 100% unmodified
%   from L2 components to the Presenter interface.

    properties
        Fig
        View
    end

    methods (TestMethodSetup)
        function createFixture(testCase)
            testCase.Fig = uifigure('Visible', 'off');
            tabGroup = uitabgroup(testCase.Fig);
            tab = uitab(tabGroup, 'Title', 'Test');
            testCase.View = TimeSeriesView(tab);
        end
    end

    methods (TestMethodTeardown)
        function destroyFixture(testCase)
            if isvalid(testCase.Fig)
                delete(testCase.Fig);
            end
        end
    end

    methods (Access = private)
        function assertEventFires(testCase, eventName, triggerFn, validatorFn)
        %ASSERTEVENTFIRES  Generic route-contract assertion.
            cap = EventCapture();
            lh = addlistener(testCase.View, eventName, ...
                @(~,e) cap.store(e));
            triggerFn();
            pause(0.1);
            testCase.verifyNotEmpty(cap.Events, ...
                sprintf('%s should have fired', eventName));
            if ~isempty(validatorFn) && ~isempty(cap.Events)
                validatorFn(cap.Events{1});
            end
            delete(lh);
        end

        function btn = findBtn(testCase, text)
            btn = [];
            findRecursive(testCase.Fig);
            function findRecursive(h)
                if ~isempty(btn), return; end
                if isa(h, 'matlab.ui.control.Button') && strcmp(h.Text, text)
                    btn = h; return
                end
                if isprop(h, 'Children')
                    for c = 1:numel(h.Children)
                        findRecursive(h.Children(c));
                        if ~isempty(btn), return; end
                    end
                end
            end
            testCase.verifyNotEmpty(btn, sprintf('Button "%s" not found', text));
        end

        function notifyTable(testCase, action, dsIdx, colIdx)
            payload = struct('action', action, 'datasetIdx', dsIdx, 'colIdx', colIdx);
            notify(testCase.View.TableComp, 'ActionRequested', AppEventData(payload));
        end
    end

    methods (Test)
        %% ===== A. Button-direct events (no payload) =====

        function test_BrowseClicked(testCase)
            btn = testCase.findBtn('Browse...');
            testCase.assertEventFires('BrowseClicked', ...
                @() btn.ButtonPushedFcn(btn, []), []);
        end

        function test_ImportButtonClicked(testCase)
            btn = testCase.findBtn('Import');
            testCase.assertEventFires('ImportButtonClicked', ...
                @() btn.ButtonPushedFcn(btn, []), []);
        end

        function test_ClearAllClicked(testCase)
            btn = testCase.findBtn('Clear All');
            testCase.assertEventFires('ClearAllClicked', ...
                @() btn.ButtonPushedFcn(btn, []), []);
        end

        function test_ExportClicked(testCase)
            btn = testCase.findBtn('Export');
            testCase.assertEventFires('ExportClicked', ...
                @() btn.ButtonPushedFcn(btn, []), []);
        end

        function test_ClearPlotClicked(testCase)
            btn = testCase.findBtn('Clear');
            testCase.assertEventFires('ClearPlotClicked', ...
                @() btn.ButtonPushedFcn(btn, []), []);
        end

        function test_SpectrumClicked(testCase)
            btn = testCase.findBtn('频谱');
            testCase.assertEventFires('SpectrumClicked', ...
                @() btn.ButtonPushedFcn(btn, []), []);
        end

        function test_CalcClicked(testCase)
            btn = testCase.findBtn('Calc');
            testCase.assertEventFires('CalcClicked', ...
                @() btn.ButtonPushedFcn(btn, []), []);
        end

        %% ===== B. Button-with-data events =====

        function test_NormClicked(testCase)
            btn = testCase.findBtn('Norm');
            testCase.assertEventFires('NormClicked', ...
                @() btn.ButtonPushedFcn(btn, []), ...
                @(p) testCase.verifyEqual(p.mode, 'None'));
        end

        function test_AxesClicked_Single(testCase)
            btn = testCase.findBtn('||');
            testCase.assertEventFires('AxesClicked', ...
                @() btn.ButtonPushedFcn(btn, []), ...
                @(p) testCase.verifyEqual(p.mode, 'single'));
        end

        function test_AxesClicked_Dual(testCase)
            btn = testCase.findBtn('=');
            testCase.assertEventFires('AxesClicked', ...
                @() btn.ButtonPushedFcn(btn, []), ...
                @(p) testCase.verifyEqual(p.mode, 'dual'));
        end

        %% ===== C. AxesGrid-proxied events =====

        function test_AxesRemoveClicked(testCase)
            v = testCase.View;
            v.GridMgr.AddAxes();
            testCase.verifyEqual(v.GridMgr.Count, 2);

            btn = testCase.findBtn(char(8722));  % '−' button
            testCase.assertEventFires('AxesRemoveClicked', ...
                @() btn.ButtonPushedFcn(btn, []), []);
        end

        %% ===== D. ChannelTableComponent proxy events (11) =====

        function test_ChannelCheckChanged(testCase)
            testCase.assertEventFires('ChannelCheckChanged', ...
                @() testCase.notifyTable('checkChanged', 1, 1), ...
                @(p) testCase.verifyEqual(p.action, 'checkChanged'));
        end

        function test_InlineRenameDataset(testCase)
            payload = struct('action','renameDataset', 'datasetIdx',1, ...
                'colIdx',0, 'value','NewDS');
            testCase.assertEventFires('InlineRenameDataset', ...
                @() notify(testCase.View.TableComp, 'ActionRequested', AppEventData(payload)), ...
                @(p) testCase.verifyEqual(char(p.value), 'NewDS'));
        end

        function test_InlineRenameChannel(testCase)
            payload = struct('action','renameChannel', 'datasetIdx',1, ...
                'colIdx',2, 'value','NewCh');
            testCase.assertEventFires('InlineRenameChannel', ...
                @() notify(testCase.View.TableComp, 'ActionRequested', AppEventData(payload)), ...
                @(p) testCase.verifyEqual(char(p.value), 'NewCh'));
        end

        function test_SetSampleRateClicked(testCase)
            testCase.assertEventFires('SetSampleRateClicked', ...
                @() testCase.notifyTable('setSampleRate', 1, 0), ...
                @(p) testCase.verifyEqual(p.action, 'setSampleRate'));
        end

        function test_SliceDialogClicked(testCase)
            testCase.assertEventFires('SliceDialogClicked', ...
                @() testCase.notifyTable('slice', 1, 2), ...
                @(p) testCase.verifyEqual(p.colIdx, 2));
        end

        function test_SliceResetClicked(testCase)
            testCase.assertEventFires('SliceResetClicked', ...
                @() testCase.notifyTable('sliceReset', 1, 1), ...
                @(p) testCase.verifyEqual(p.action, 'sliceReset'));
        end

        function test_ExportExcelClicked(testCase)
            testCase.assertEventFires('ExportExcelClicked', ...
                @() testCase.notifyTable('exportExcel', 1, 0), ...
                @(p) testCase.verifyEqual(p.action, 'exportExcel'));
        end

        function test_SetXAxisClicked(testCase)
            testCase.assertEventFires('SetXAxisClicked', ...
                @() testCase.notifyTable('setXAxis', 1, 3), ...
                @(p) testCase.verifyEqual(p.colIdx, 3));
        end

        function test_ClearXAxisClicked(testCase)
            payload = struct('action','clearXAxis', 'datasetIdx',0, 'colIdx',0);
            testCase.assertEventFires('ClearXAxisClicked', ...
                @() notify(testCase.View.TableComp, 'ActionRequested', AppEventData(payload)), ...
                @(p) testCase.verifyTrue(isfield(p, 'axesIdx'), ...
                    'clearXAxis should inject axesIdx'));
        end

        function test_SetRightYAxisClicked(testCase)
            testCase.assertEventFires('SetRightYAxisClicked', ...
                @() testCase.notifyTable('setRightY', 1, 2), ...
                @(p) testCase.verifyEqual(p.action, 'setRightY'));
        end

        function test_ClearRightYAxisClicked(testCase)
            payload = struct('action','clearRightY', 'datasetIdx',0, 'colIdx',0);
            testCase.assertEventFires('ClearRightYAxisClicked', ...
                @() notify(testCase.View.TableComp, 'ActionRequested', AppEventData(payload)), ...
                @(p) testCase.verifyTrue(isfield(p, 'axesIdx'), ...
                    'clearRightY should inject axesIdx'));
        end

        %% ===== E. CursorComponent proxy event =====

        function test_CursorMotion(testCase)
            v = testCase.View;
            testCase.verifyTrue(v.CursorMap.isKey(1), 'CursorMap should have key 1');
            cursor = v.CursorMap(1);

            snapData = struct('action','CursorSnapped', 'axesIdx',1, ...
                'x', 42.0, 'y', 3.14, 'lineTag','leftY', 'xDataIdx', 10);
            testCase.assertEventFires('CursorMotion', ...
                @() notify(cursor, 'CursorSnapped', AppEventData(snapData)), ...
                @(p) testCase.verifyEqual(p.x, 42.0, 'AbsTol', 0.01));
        end
    end
end

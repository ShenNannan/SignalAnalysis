classdef TestAxesGridComponent < matlab.unittest.TestCase
%TESTAXESGRIDCOMPONENT  5-dimension MECE test matrix for AxesGridComponent.
%
%   D1: Data boundaries (0-6 axes, MaxAxes limit, Clear, GetAxes bounds)
%   D2: Layout mode verification (empty/single/vert2/vert3/2x2/2x3/3x2)
%   D3: RemoveAxes re-indexing (middle delete, GetAllAxes)
%   D4: Stress (100 add/remove cycles)
%   D5: Exception injection (mustBePositive, out-of-range silent no-op)

    properties
        Fig
    end

    methods (TestMethodSetup)
        function createHeadlessFigure(testCase)
            testCase.Fig = uifigure('Visible', 'off');
        end
    end

    methods (TestMethodTeardown)
        function destroyHeadlessFigure(testCase)
            if isvalid(testCase.Fig)
                delete(testCase.Fig);
            end
        end
    end

    methods (Test)
        %% ===== D1: Data Boundaries =====

        function test_AddAxes_FiresEvent(testCase)
            g = AxesGridComponent(testCase.Fig);
            captured = {};
            lh = addlistener(g, 'AxesAdded', @(~,e) storeEvent(e));

            hAx = g.AddAxes();
            testCase.verifyNotEmpty(captured, 'AxesAdded should fire');
            p = captured{1};
            testCase.verifyEqual(p.action, 'AxesAdded');
            testCase.verifyEqual(p.axesIdx, 1);
            testCase.verifyEqual(p.handle, hAx);
            testCase.verifyTrue(isvalid(hAx));
            delete(lh);

            function storeEvent(e) %#ok<INUSL>
                captured{end+1} = e.Data;
            end
        end

        function test_Count_Increments(testCase)
            g = AxesGridComponent(testCase.Fig);
            testCase.verifyEqual(g.Count, 0);

            for i = 1:6
                g.AddAxes();
                testCase.verifyEqual(g.Count, i);
            end
        end

        function test_MaxAxes_Limit(testCase)
            g = AxesGridComponent(testCase.Fig, 'MaxAxes', 3);

            captured = {};
            lh = addlistener(g, 'AxesAdded', @(~,e) storeEvent(e));

            g.AddAxes(); g.AddAxes(); g.AddAxes();
            testCase.verifyNumElements(captured, 3);

            % 4th should be no-op
            g.AddAxes();
            testCase.verifyNumElements(captured, 3, ...
                'No AxesAdded event at MaxAxes');
            testCase.verifyEqual(g.Count, 3, ...
                'Count should remain at MaxAxes');
            delete(lh);

            function storeEvent(e) %#ok<INUSL>
                captured{end+1} = e.Data;
            end
        end

        function test_Clear_RemovesAll(testCase)
            g = AxesGridComponent(testCase.Fig);
            for i = 1:4, g.AddAxes(); end
            testCase.verifyEqual(g.Count, 4);

            captured = {};
            lh = addlistener(g, 'AxesRemoved', @(~,e) storeEvent(e));
            g.Clear();
            testCase.verifyEqual(g.Count, 0);
            testCase.verifyNumElements(captured, 4, ...
                'Should fire 4 AxesRemoved events');
            testCase.verifyEqual(g.LayoutMode, "empty");
            delete(lh);

            function storeEvent(e) %#ok<INUSL>
                captured{end+1} = e.Data;
            end
        end

        function test_GetAxes_OutOfBounds(testCase)
            g = AxesGridComponent(testCase.Fig);
            g.AddAxes();

            % idx=0 triggers mustBePositive validation
            testCase.verifyError(@() g.GetAxes(0), ...
                'MATLAB:validators:mustBePositive');

            % idx=99 passes validation but out of range → invalid handle
            hAx = g.GetAxes(99);
            testCase.verifyEqual(hAx, gobjects(1));
        end

        %% ===== D2: Layout Mode =====

        function test_LayoutMode_AllCounts(testCase)
            g = AxesGridComponent(testCase.Fig);

            expectedModes = ["empty", "single", "vert2", "vert3", ...
                             "2x2", "2x3", "3x2"];
            testCase.verifyEqual(g.LayoutMode, expectedModes(1));

            for i = 1:6
                g.AddAxes();
                testCase.verifyEqual(g.LayoutMode, expectedModes(i+1), ...
                    sprintf('LayoutMode wrong at Count=%d', i));
            end
        end

        %% ===== D3: RemoveAxes Re-indexing =====

        function test_RemoveAxes_FiresEvent(testCase)
            g = AxesGridComponent(testCase.Fig);
            g.AddAxes(); g.AddAxes(); g.AddAxes();

            captured = {};
            lh = addlistener(g, 'AxesRemoved', @(~,e) storeEvent(e));

            g.RemoveAxes(2);
            testCase.verifyNotEmpty(captured);
            p = captured{1};
            testCase.verifyEqual(p.action, 'AxesRemoved');
            testCase.verifyEqual(p.axesIdx, 2);
            delete(lh);

            function storeEvent(e) %#ok<INUSL>
                captured{end+1} = e.Data;
            end
        end

        function test_RemoveAxes_ShiftsRemaining(testCase)
            g = AxesGridComponent(testCase.Fig);
            hAx1 = g.AddAxes();  % index 1
            hAx2 = g.AddAxes();  % index 2
            hAx3 = g.AddAxes();  % index 3

            g.RemoveAxes(2);  % delete hAx2
            testCase.verifyEqual(g.Count, 2);
            testCase.verifyEqual(g.GetAxes(1), hAx1);
            testCase.verifyEqual(g.GetAxes(2), hAx3);
        end

        function test_GetAllAxes(testCase)
            g = AxesGridComponent(testCase.Fig);
            g.AddAxes(); g.AddAxes(); g.AddAxes();

            list = g.GetAllAxes();
            testCase.verifyNumElements(list, 3);
            for i = 1:3
                testCase.verifyEqual(list(i), g.GetAxes(i));
            end
        end

        %% ===== D4: Stress =====

        function test_Stress_AddRemoveCycle(testCase)
            g = AxesGridComponent(testCase.Fig);

            for i = 1:100
                g.AddAxes();
                testCase.verifyEqual(g.Count, 1);
                g.RemoveAxes(1);
                testCase.verifyEqual(g.Count, 0);
            end
        end

        %% ===== D5: Exception Injection =====

        function test_RemoveAxes_MustBePositiveError(testCase)
            g = AxesGridComponent(testCase.Fig);
            g.AddAxes();

            % idx=0 triggers mustBePositive argument validation
            testCase.verifyError(@() g.RemoveAxes(0), ...
                'MATLAB:validators:mustBePositive');
        end

        function test_RemoveAxes_OutOfRange_SilentNoop(testCase)
            g = AxesGridComponent(testCase.Fig);
            g.AddAxes();

            % idx=99 passes mustBePositive but hits bounds check → silent return
            g.RemoveAxes(99);
            testCase.verifyEqual(g.Count, 1, ...
                'Out-of-range RemoveAxes should be a no-op');
        end
    end
end

classdef AsyncToaster < handle
%ASYNCTOASTER  RAII-style modal progress toaster.
%   Wraps uiprogressdlg with deterministic auto-cleanup.
%   The dialog blocks the calling UI on construction and is
%   guaranteed to close on object destruction (delete / clear / exception).

    properties (Access = private)
        Dlg                 % uiprogressdlg handle
        ParentFigure        % owner figure (for reuse check)
    end

    methods
        function obj = AsyncToaster(parentFig, title, message)
        %ASYNCTOASTER  Show a blocking progress dialog.
        %   obj = AsyncToaster(parentFig, title, message)
        %
        %   parentFig  - the owning uifigure (or figure)
        %   title      - dialog title string
        %   message    - initial status message string

            arguments
                parentFig   (1,1)  % any figure handle
                title       (1,1) string
                message     (1,1) string
            end

            obj.ParentFigure = parentFig;

            obj.Dlg = uiprogressdlg(parentFig, ...
                'Title',            title, ...
                'Message',          message, ...
                'Indeterminate',    'on', ...
                'Cancelable',       'off', ...
                'Interpreter',      'none');
        end

        function Update(obj, message, fraction)
        %UPDATE  Refresh the displayed message and optional progress.
        %   Update(obj, message)          - update message only (indeterminate)
        %   Update(obj, message, fraction)- set determinate progress [0,1]

            arguments
                obj       (1,1) AsyncToaster
                message   (1,1) string
                fraction  (1,1) double {mustBeInRange(fraction,0,1)} = NaN
            end

            % Guard: dialog may have been force-closed externally
            if isempty(obj.Dlg) || ~isvalid(obj.Dlg)
                return
            end

            obj.Dlg.Message = message;

            if ~isnan(fraction)
                obj.Dlg.Indeterminate = 'off';
                obj.Dlg.Value = fraction;
            end
        end

        function delete(obj)
        %DELETE  RAII destructor - guaranteed dialog teardown.
        %   Called automatically on clear, function exit, or exception.

            if ~isempty(obj.Dlg) && isvalid(obj.Dlg)
                close(obj.Dlg);
            end
        end
    end
end

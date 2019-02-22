classdef PupilFillMet3 < mic.Base
    
    properties (Constant)
        
        dWidth = 1250
        dHeight = 720
        
    end
    
    properties
    end
    
    properties (Access = private)
        
        % {handle 1x1}
        hFigure
        
        % {mic.ui.common.Button 1x1}
        uiButtonSet
        
        % {mic.ui.common.Edit 1x1}
        uiEditOffsetX
        
        % {mic.ui.common.Edit 1x1}
        uiEditOffsetY
        
        % {PupilFillGenerator 1x1}
        pupilFillGenerator
        
        % {char 1xm}
        cDirSave
        
        % {char 1xm}
        cDirSaveTfw
        
        cIpAfg = 'TCPIP0::cxro4.lbl.gov::inst0::INSTR'
        cUsbAfg = 'USB::0x0699::0x0343::c011587::INSTR'
    end
    
    methods
        
        function this = PupilFillMet3(varargin)
                      
            this.cDirSave = this.getDirSaveDefault();
            this.cDirSaveTfw = this.getDirSaveDefaultTfw();
            
            % Apply varargin
            
            for k = 1 : 2: length(varargin)
                % this.msg(sprintf('passed in %s', varargin{k}));
                if this.hasProp( varargin{k})
                    this.msg(sprintf('settting %s', varargin{k}), 3);
                    this.(varargin{k}) = varargin{k + 1};
                end
            end
            
            this.init();
            this.build();
            this.loadFromDisk();
        end
        
        
        
        function st = save(this)
           st = struct();
           st.pupilFillGenerator = this.pupilFillGenerator.save();
           st.uiEditOffsetX = this.uiEditOffsetX.save();
           st.uiEditOffsetY = this.uiEditOffsetY.save();
        end
        
        function load(this, st)
           this.pupilFillGenerator.load(st.pupilFillGenerator);
           if isfield(st, 'uiEditOffsetX')
               this.uiEditOffsetX.load(st.uiEditOffsetX);
           end
           
           if isfield(st, 'uiEditOffsetY')
               this.uiEditOffsetY.load(st.uiEditOffsetY);
           end
        end
        
        function delete(this)
            this.saveToDisk();
            delete(this.pupilFillGenerator)
        end
        
       
        
        
    end
    
    
    methods (Access = private)
        
        function build(this)
            
            if ishghandle(this.hFigure)
                % Bring to front
                figure(this.hFigure);
                return
            end
            
            this.buildFigure();
            this.buildPupilFillGenerator();
            this.buildButtonSet();
            this.buildEditOffset();
            
        end
        
        
        function init(this)
            this.initPupilFillGenerator();
            this.initButtonSet();
            this.initEditOffset();
        end
        
        function initEditOffset(this)
            
            this.uiEditOffsetX = mic.ui.common.Edit(...
                'cLabel', 'Offset X', ...
                'cType', 'd' ...
                ...%'fhDirectCallback', @this.onWaveformProperty ...
            ); 
            this.uiEditOffsetX.setMin(-1);
            this.uiEditOffsetX.setMax(1);
            this.uiEditOffsetX.set(0);
            
            this.uiEditOffsetY = mic.ui.common.Edit(...
                'cLabel', 'Offset Y', ...
                'cType', 'd' ...
                ...%'fhDirectCallback', @this.onWaveformProperty ...
            ); 
            this.uiEditOffsetY.setMin(-1);
            this.uiEditOffsetY.setMax(1);
            this.uiEditOffsetY.set(0);
                
        end
        
        function initButtonSet(this)
            
            this.uiButtonSet = mic.ui.common.Button(...
                'cText', 'Set Illumination', ...
                'fhDirectCallback', @this.onButtonSet ...
            );
        end
        
        function initPupilFillGenerator(this)
            this.pupilFillGenerator = PupilFillGenerator();
        end
        
        function buildPupilFillGenerator(this)
            this.pupilFillGenerator.build(this.hFigure, 10, 10);
        end
        
        function onButtonSet(this, src, evt)
                       
            st = this.pupilFillGenerator.get();
            x = st.x;
            y = st.y;
            
            % Offset
            x = x + this.uiEditOffsetX.get();
            y = y + this.uiEditOffsetY.get();
            
            % Scale to [-5 5] V
            x = x * 5;
            y = y * 5;
            
            t = st.t;
            
            % The DLL uses a weird method where it loads the tfw file
            % from disk when it writes it to the AFT
            
            % Generate TFW files for x and y values.  Filename will
            % be the current timestamp
            
            mic.Utils.checkDir(this.cDirSaveTfw);
            
            cDate = datestr(datevec(now),'yyyy-mm-dd HH-MM-SS');
            cPathTfwX = fullfile(this.cDirSaveTfw, sprintf('%s X.tfw', cDate));
            cPathTfwY = fullfile(this.cDirSaveTfw, sprintf('%s Y.tfw', cDate));
            
            tfw_write(x, cPathTfwX);
            tfw_write(y, cPathTfwY);
                        
            % Setup some AFG config values based on the waveform
            % The min vpp the scope config can accept is .02 Volts. When
            % you want to run a DC signal, you must set the vpp value to
            % it's min i.e., .02 Volts and set the offset to the DC level
            % you desire.  The high_level and low_level settings must also
            % be set up accordingly.  Set high_level to DC_level + .02/2
            % and set low_level to DC_level - .02/2; this way the
            % difference high_level - low_level = vpp, as it should.
            
            highX = max(x);
            highY = max(y);
            
            lowX = min(x);
            lowY = min(y);
            
            if highX - lowX < 0.02
                % Effectively DC. Adjust so the diff is at least 0.02
                highX = mean(x) + 0.01;
                lowX = mean(x) - 0.01;
            end
            
            if highY - lowY < 0.02
                % Effectively DC.  Adjust so the diff is at least 0.02
                highY = mean(y) + 0.01;
                lowY = mean(y) - 0.01;
            end
            
            period = max(t);
            freq_kHz = 1/period/1000;
            
            
            dllPath = fullfile(this.getDirDll(), 'libAFG3102.dll');
            hPath = fullfile(this.getDirDll(), 'libAFG3102.h');
            
            % Make sure you install Microsoft Visual C++
            % 2008 SP1 Redistributable Package (x86)
            loadlibrary(dllPath,hPath)

            return_IP = calllib('libAFG3102', 'Init', this.cIpAfg);

            % If connecting via IP failed, try USB
            if return_IP < 0 
                return_USB = calllib('libAFG3102', 'Init', this.cUsbAfg);
                if return_USB < 0
                    a = 'ERROR: Could not connect via IP or USB.  Contact Ron Tackeberry.';
                    unloadlibrary libAFG3102      
                    msgbox(a,'CONNECTION ERROR','warn')
                    return;
                end
            end

            calllib('libAFG3102', 'outputOff',1);
            calllib('libAFG3102', 'outputOff',2);
            calllib('libAFG3102', 'setMemoryStateRecall','OFF');
            calllib('libAFG3102', 'syncFrequency');
            calllib('libAFG3102', 'setVoltageUnit',1,'VPP');
            calllib('libAFG3102', 'setVoltageUnit',2,'VPP');
            calllib('libAFG3102', 'setHighLevel',1, highX, 'V');
            calllib('libAFG3102', 'setHighLevel',2, highY, 'V');
            calllib('libAFG3102', 'setLowLevel',1, lowX, 'V');
            calllib('libAFG3102', 'setLowLevel',2, lowY, 'V');
            calllib('libAFG3102', 'setHighLimit',1, 5, 'V');
            calllib('libAFG3102', 'setHighLimit',2, 5, 'V');
            calllib('libAFG3102', 'setLowLimit',1, -5, 'V');
            calllib('libAFG3102', 'setLowLimit',2, -5, 'V');
            calllib('libAFG3102', 'setFrequency',1, freq_kHz,'KHz');
            calllib('libAFG3102', 'setFrequency',2, freq_kHz,'KHz');
            calllib('libAFG3102', 'loadUser1FromFile', cPathTfwX);
            calllib('libAFG3102', 'loadUser2FromFile', cPathTfwY);
            calllib('libAFG3102', 'outputOn', 1);
            calllib('libAFG3102', 'outputOn', 2);
            calllib('libAFG3102', 'close');
            unloadlibrary libAFG3102
            
        end
        
        function buildButtonSet(this)
            dLeft = 30;
            dTop = 670;
            this.uiButtonSet.build(this.hFigure, dLeft, dTop, 185, 24);
        end
        
        function buildEditOffset(this)
            
            dWidth = 80;
            dLeft = 230;
            dTop = 670;
            this.uiEditOffsetX.build(this.hFigure, dLeft, dTop, dWidth, 24);
            
            dLeft = 320;
            this.uiEditOffsetY.build(this.hFigure, dLeft, dTop, dWidth, 24);
        end
        
        function buildFigure(this)
            
            dScreenSize = get(0, 'ScreenSize');
            this.hFigure = figure( ...
                'NumberTitle', 'off', ...
                'MenuBar', 'none', ...
                'Name', 'MET3 Pupil Fill', ...
                'Color', [120 120 120] ./ 255, ...
                'Position', [ ...
                    (dScreenSize(3) - this.dWidth)/2 ...
                    (dScreenSize(4) - this.dHeight)/2 ...
                    this.dWidth ...
                    this.dHeight ...
                 ]... % left bottom width height
            );
            
            
        end
        
        function c = getDirDll(this)
            cDirThis = fileparts(mfilename('fullpath'));
            c = fullfile( ...
                cDirThis, ...
                '..', ...
                'vendor', ...
                'retackeberry' ...
            );
            c = mic.Utils.path2canonical(c);
            
            % Test if the old one works
            % c = 'C:\Documents and Settings\bl12user\My Documents\MATLAB\PupilSoftware_v10\Core'
        end
        
        function c = getDirSaveDefault(this)
            
            cDirThis = fileparts(mfilename('fullpath'));
            c = fullfile( ...
                cDirThis, ...
                '..', ...
                'save' ...
            );
            c = mic.Utils.path2canonical(c);
            
        end
        
        function c = getDirSaveDefaultTfw(this)
            
            cDirThis = fileparts(mfilename('fullpath'));
            c = fullfile( ...
                cDirThis, ...
                '..', ...
                'tfw' ...
            );
            c = mic.Utils.path2canonical(c);
            
        end
        
        
        function saveToDisk(this)
            this.msg('saveToDisk()');
            st = this.save();
            save(this.file(), 'st');
        end
        
        function loadFromDisk(this)
            if exist(this.file(), 'file') == 2
                fprintf('loadFromDisk()\n');
                load(this.file()); % populates variable st in local workspace
                this.load(st);
            end
        end
        
        function c = file(this)
            mic.Utils.checkDir(this.cDirSave);
            c = fullfile(...
                this.cDirSave, ...
                ['saved-state', '.mat']...
            );
        end
        
        
    end
    
end


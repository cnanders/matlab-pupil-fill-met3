classdef PupilFillMet3 < mic.Base
    
    properties (Constant)
        
        dWidth = 1250
        dHeight = 700
        
    end
    
    properties
    end
    
    properties (Access = private)
        
        % {handle 1x1}
        hFigure
        
        % {mic.ui.common.Button 1x1}
        uiButtonSet
        
        % {PupilFillGenerator 1x1}
        pupilFillGenerator
        
        % {char 1xm}
        cDirSave
        
        % {char 1xm}
        cDirSaveTfw
        
        cIpAfg = 'TCPIP0::cxro4.lbl.gov::inst0::INSTR'
        cUsbAfg = 'USB::0x0699::0x0343::C011593::INSTR'
    end
    
    methods
        
        function this = PupilFillMet3(varargin)
                      
            this.cDirSave = this.getDefaultDirSave();
            this.cDirSaveTfw = this.getDefaultDirSaveTfw();
            
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
        end
        
        function load(this, st)
           this.pupilFillGenerator.load(st.pupilFillGenerator);
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
            
        end
        
        
        function init(this)
            this.initPupilFillGenerator();
            this.initButtonSet();
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
            x = st.x * 5;
            y = st.y * 5;
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
            tfw_write(y, cPathTfwX);
                        
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
            
            
            dllPath = fullfile(pwd, '..', 'vendor', 'retackeberry', 'libAFG3102.dll');
            hPath = fullfile(pwd, '..', 'vendor', 'retackeberry', 'libAFG3102.h');
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
            this.uiButtonSet.build(this.hFigure, 30, 670, 185, 24);
        end
        
        function buildFigure(this)
            
            dScreenSize = get(0, 'ScreenSize');
            this.hFigure = figure( ...
                'NumberTitle', 'off', ...
                'MenuBar', 'none', ...
                'Name', 'MET3 Pupil Fill', ...
                'Position', [ ...
                    (dScreenSize(3) - this.dWidth)/2 ...
                    (dScreenSize(4) - this.dHeight)/2 ...
                    this.dWidth ...
                    this.dHeight ...
                 ]... % left bottom width height
            );
            
            
        end
        
        function c = getDefaultDirSave(this)
            
            cDirThis = fileparts(mfilename('fullpath'));
            c = fullfile( ...
                cDirThis, ...
                '..', ...
                'save' ...
            );
            
        end
        
        function c = getDefaultDirSaveTfw(this)
            
            cDirThis = fileparts(mfilename('fullpath'));
            c = fullfile( ...
                cDirThis, ...
                '..', ...
                'tfw' ...
            );
            
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


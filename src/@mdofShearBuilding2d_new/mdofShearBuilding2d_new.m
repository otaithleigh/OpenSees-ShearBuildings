classdef mdofShearBuilding2d_new < MasterBuilding
% MDOFSHEARBUILDING2D

properties (Constant)
    nDOF = 1;
end

methods

%######################### Constructor and set methods ########################%
function obj = mdofShearBuilding2d_new(nStories)
    obj@MasterBuilding(nStories)
    obj.includeExplicitPDelta = false;
end

%############################### Model functions ##############################%
function node = storyNodes(obj, i)
% STORYNODES  Return the node tag corresponding to the requested story, where 0 is the ground floor
    if (i > obj.nStories) || (i < 0)
        error('requested floor: %i does not exist', i)
    end
    node = i;
end

function s = controlNode(obj)
% CONTROLNODE  Return the node tag corresponding to the control story
    if isequal(obj.controlStory,'roof')
        s = obj.nStories;
    else
        s = obj.controlStory;
    end
end

function tag = springTags(obj, i)
% SPRINGTAGS  Return the element tag corresponding to the spring at the requested floor
    if (i > obj.nStories) || (i < 1)
        error('requested spring: %i does not exist', i)
    end
    tag = i;
end

function constructBuilding(obj, fid)
% CONSTRUCTBUILDING  Create the OpenSees model based on current properties
%
%    CONSTRUCTBUILDING(obj, fid) writes the OpenSees code that represents
%       the model to the file specified by fid.
%
    fprintf(fid,'# Units: %s, %s, %s\n\n',obj.units.force,obj.units.length,obj.units.time);
    fprintf(fid,'source [file join {%s} {updateRayleighDamping.tcl}]\n',obj.pathOf.tclfunctions);
    fprintf(fid,'\n');
    fprintf(fid,'#################################### Model #####################################\n');
    fprintf(fid,'model BasicBuilder -ndm 1 -ndf 1\n\n');
    fprintf(fid,'#----------------------------------- Nodes ------------------------------------#\n');
    fprintf(fid,'node %i 0\n', obj.storyNodes(0));
    for i = 1:obj.nStories
        fprintf(fid,'node %i 0 -mass %g\n', obj.storyNodes(i), obj.storyMass(i));
    end
    fprintf(fid,'\n');
    fprintf(fid,'#-------------------------------- Constraints ---------------------------------#\n');
    fprintf(fid,'fix %i 1\n\n', obj.storyNodes(0));
    fprintf(fid,'#--------------------------------- Materials ----------------------------------#\n');
    for i = 1:length(obj.storySpringDefinition)
        fprintf(fid,'%s\n',obj.storySpringDefinition{i});
    end
    fprintf(fid,'\n');
    fprintf(fid,'#---------------------------------- Elements ----------------------------------#\n');
    for i = 1:obj.nStories
        fprintf(fid,'element zeroLength %i %i %i -mat %i -dir 1 -doRayleigh 1\n',...
                obj.springTags(i), obj.storyNodes(i-1), obj.storyNodes(i), obj.springTags(i));
    end
    fprintf(fid,'\n');

end %function:constructBuilding

%% Analyses

function results = pushover(obj,F,type,varargin)
    %% PUSHOVER Perform a pushover analysis
    %
    %   results = PUSHOVER(obj,F,type,typeArg) performs a pushover
    %       analysis with load distribution specified by F and end
    %       condition defined by type and typeArg.
    %
    %   type accepts the following options:
    %       targetDrift
    %       targetPostPeakRatio
    %
    %   results has the following fields:
    %
    %   F                       Force ratios
    %   targetDrift             Target drift for analysis
    %   targetPostPeakRatio     Target post peak ratio
    %   textOutput              Console output from OpenSees
    %   exitStatus              Reports whether analysis was successful
    %   totalDrift              Time history of total drift of stories
    %   storyShear              Time history of story shears
    %   storyDrift              Time history of story drifts
    %   appliedStoryForce       Time history of applied forces
    %   roofDrift               Time history of total roof drift
    %   baseShear               Time history of base shear
    %

    assert(isnumeric(F) & isvectorsize(F,obj.nStories),...
        'F should be a numeric verctor of length %i (number of stories)',obj.nStories);
    if iscolumn(F)
        F = F';
    end

    % Initialize Results
    results = struct;
    results.F = F;

    switch lower(type)
        case 'targetdrift'
            targetDrift      = varargin{1};

            results.targetDrift = targetDrift;
        case 'targetpostpeakratio'
            targetPostPeakRatio = varargin{1};

            results.targetPostPeakRatio = targetPostPeakRatio;
        otherwise
            error('Unknown analysis type: %s',type);
    end

    % Filenames
    filename_input          = obj.scratchFile('mdofShearBuilding2d_input.tcl');
    filename_output_def     = obj.scratchFile('mdofShearBuilding2d_disp.out');
    filename_output_force   = obj.scratchFile('mdofShearBuilding2d_force.out');

    % Create .tcl file
    fid = fopen(filename_input,'w');

    obj.constructBuilding(fid)

    fprintf(fid,'timeSeries Linear 1\n');
    fprintf(fid,'pattern Plain 1 1 {\n');
    for i = 1:obj.nStories
        if F(i) ~= 0
            fprintf(fid,'    load %i %g \n',i,F(i));
        end
    end
    fprintf(fid,'} \n');

    fprintf(fid,'recorder Node -file {%s} -time -nodeRange 1 %i -dof 1 disp \n',filename_output_def,obj.nStories);
    fprintf(fid,'recorder Element -file {%s} -eleRange 1 %i force \n',filename_output_force,obj.nStories);
    fprintf(fid,'record \n');
    fprintf(fid,'system UmfPack \n');
    % constraints
    switch obj.optionsPushover.constraints.type
    case 'Penalty'
        fprintf(fid,'constraints Penalty %g %g\n',obj.optionsPushover.constraints.penalty.alphaS,...
                                                  obj.optionsPushover.constraints.penalty.alphaM);
    otherwise
        fprintf(fid,'constraints %s\n',obj.optionsPushover.constraints.type);
    end
    % test
    testArgs = cell(length(obj.optionsPushover.test.tolerance),1);
    for i = 1:length(obj.optionsPushover.test.tolerance)
        testArgs{i} = sprintf('%s %g %i %i %i',obj.optionsPushover.test.type,...
                                               obj.optionsPushover.test.tolerance(i),...
                                               obj.optionsPushover.test.iterations,...
                                               obj.optionsPushover.test.print,...
                                               obj.optionsPushover.test.normType);
    end

    fprintf(fid,'numberer RCM \n');
    fprintf(fid,'integrator DisplacementControl %i 1 %g\n',obj.controlStory1,obj.pushover_stepSize);
    fprintf(fid,'analysis Static \n');

    switch lower(type)
        case 'targetdrift'
            fprintf(fid,'algorithm Newton\n');
            fprintf(fid,'set ok [analyze %i]\n',ceil(targetDrift/obj.pushover_stepSize));
            fprintf(fid,'if { $ok != 0 } {\n');
            fprintf(fid,'    exit 1\n');
            fprintf(fid,'}\n');
        case 'targetpostpeakratio'
            fprintf(fid,'set currentLoad [getTime]\n');
            fprintf(fid,'set maxLoad $currentLoad\n');
            fprintf(fid,'while { $currentLoad >= [expr %g*$maxLoad] } {\n',targetPostPeakRatio);
            fprintf(fid,'    algorithm %s\n',obj.optionsPushover.algorithm.type{1});
            fprintf(fid,'    test %s\n',testArgs{1});
            fprintf(fid,'    set ok [analyze 1]\n');
            for i = 1:length(testArgs)
                if i == 1; k = 2; else; k = 1; end
                for j = k:length(obj.optionsPushover.algorithm.type)
                    fprintf(fid,'    if { $ok != 0 } {\n');
                    fprintf(fid,'        algorithm %s\n',obj.optionsPushover.algorithm.type{j});
                    fprintf(fid,'        test %s\n',testArgs{i});
                    fprintf(fid,'        set ok [analyze 1]\n');
                    fprintf(fid,'    }\n');
                end
            end
            fprintf(fid,'    if { $ok != 0 } {\n');
            fprintf(fid,'        exit 2\n');
            fprintf(fid,'    }\n');
            fprintf(fid,'    set currentLoad [getTime]\n');
            fprintf(fid,'    if { $currentLoad > $maxLoad } {\n');
            fprintf(fid,'        set maxLoad $currentLoad\n');
            fprintf(fid,'    }\n');
            fprintf(fid,'    if { [nodeDisp %i 1] > %g } {\n',obj.controlStory1,obj.pushover_maxDrift);
            fprintf(fid,'        exit 3\n');
            fprintf(fid,'    }\n');
            fprintf(fid,'}\n');
        otherwise
            error('Unknown analysis type: %s',type);
    end

    fprintf(fid,'exit 1 \n');
    fclose(fid);

    % Run OpenSees
    [status, result] = obj.runOpenSees(filename_input);
    results.textOutput = result;
    switch status
        case 1
            results.exitStatus = 'Analysis Successful';
        case 2
            results.exitStatus = 'Analysis Failed';
        case 3
            results.exitStatus = 'Peak Drift Reached';
        otherwise
            fprintf('%s\n',result);
            error('Analysis Failed in Unknown Manner (exit code: %i)',status);
    end

    % Read Results
    temp = dlmread(filename_output_def);
    time = temp(:,1);
    results.totalDrift = temp(:,2:end);
    temp = dlmread(filename_output_force);
    results.storyShear = temp(:,2:2:end);

    % Computed Results
    storyDrift = results.totalDrift;
    storyDrift(:,2:end) = storyDrift(:,2:end)-storyDrift(:,1:(end-1));
    results.storyDrift = storyDrift;
    results.appliedStoryForce = time*F;
    results.roofDrift = results.totalDrift(:,end);
    results.baseShear = results.storyShear(:,1);

    % Analysis
    if strcmp(results.exitStatus,'Analysis Successful')
        results.peakShear = max(results.baseShear);
        peakIndex = results.baseShear == results.peakShear;
        results.peakTotalDrift = results.totalDrift(peakIndex,:);
        peakStoryDrift = results.storyDrift(peakIndex,:);

        postPeakIndex = results.roofDrift > results.roofDrift(peakIndex);
        postPeakShear = results.baseShear(postPeakIndex);
        postPeakTotalDrift = results.totalDrift(postPeakIndex,:);
        postPeakStoryDrift = results.storyDrift(postPeakIndex,:);

        results.peak80Shear = 0.8*results.peakShear;
        results.peak80TotalDrift = interp1(postPeakShear,postPeakTotalDrift,results.peak80Shear);
        peak80StoryDrift = interp1(postPeakShear,postPeakStoryDrift,results.peak80Shear);

        results.peakStoryDriftRatio   = peakStoryDrift./obj.storyHeight;
        results.peak80StoryDriftRatio = peak80StoryDrift./obj.storyHeight;
    end

    % Clean Folder
    if obj.deleteFilesAfterAnalysis
        delete(filename_input,filename_output_def,filename_output_force);
    end
end %function:pushover

function results = responseHistory(obj,groundMotionFilename,dt,SF,tend,gmID,indexNum)
    %% RESPONSEHISTORY Perform response history analysis
    %
    %   results = RESPONSEHISTORY(obj,gmFile,dt,SF,tend,gmID,indexNum)
    %       Returns the results of a response history analysis of obj
    %       subject to ground motion stored in gmFile with timestep dt
    %       scaled by SF. Analysis concludes at tend. gmID and indexNum
    %       are used for incremental dynamic analyses and are optional
    %       if an IDA is not being conducted.
    %
    %   results has the following fields:
    %
    %   gmID         -
    %   indexNum     -
    %   SF           - Scale factor used in the analysis
    %   textOutput   - Text output from OpenSees
    %   groundMotion - Scaled ground motion used as input
    %   totalDrift   - Time history of the total drift of each story
    %   storyShear   - Time history of story shears
    %   storyDrift   - Time history of story drifts
    %   roofDrift    - Time history of the total roof drift
    %   baseShear    - Time history of the base shear
    %

    % Initialize Results
    results = struct;
    if nargin < 6
        gmID = '01a';
        indexNum = 1;
    else
        results.gmID = gmID;
        results.indexNum = indexNum;
    end
    results.SF = SF;

    % Filenames
    filename_input              = obj.scratchFile(sprintf('mdofShearBuilding2d_input_%s_%i.tcl',gmID,indexNum));
    filename_output_timeSeries  = obj.scratchFile(sprintf('mdofShearBuilding2d_timeSeries_%s_%i.out',gmID,indexNum));
    filename_output_def         = obj.scratchFile(sprintf('mdofShearBuilding2d_disp_%s_%i.out',gmID,indexNum));
    filename_output_vel         = obj.scratchFile(sprintf('mdofShearBuilding2d_vel_%s_%i.out',gmID,indexNum));
    filename_output_force       = obj.scratchFile(sprintf('mdofShearBuilding2d_force_%s_%i.out',gmID,indexNum));

    % Create .tcl file
    fid = fopen(filename_input,'w');

    writeFunction_updateRayleighDamping(fid)
    obj.constructBuilding(fid)

    fprintf(fid,'timeSeries Path 1 -dt %g -filePath {%s} -factor %g\n',dt,groundMotionFilename,SF);
    fprintf(fid,'pattern UniformExcitation 1 1 -accel 1\n');

    fprintf(fid,'recorder Node -file {%s} -timeSeries 1 -node 0 -dof 1 accel\n',filename_output_timeSeries);
    fprintf(fid,'recorder Node -file {%s} -time -nodeRange 1 %i -dof 1 disp \n',filename_output_def,obj.nStories);
    fprintf(fid,'recorder Node -file {%s} -time -nodeRange 1 %i -dof 1 vel  \n',filename_output_vel,obj.nStories);
    fprintf(fid,'recorder Element -file {%s} -eleRange 1 %i force \n',filename_output_force,obj.nStories);
    fprintf(fid,'record \n');

    fprintf(fid,'system UmfPack \n');
    switch obj.optionsResponseHistory.constraints.type
    case 'Penalty'
        fprintf(fid,'constraints Penalty %g %g\n',obj.optionsResponseHistory.constraints.penalty.alphaS,...
                                                  obj.optionsResponseHistory.constraints.penalty.alphaM);
    otherwise
        fprintf(fid,'constraints %s\n',obj.optionsResponseHistory.constraints.type);
    end
    % test
    testArgs = cell(length(obj.optionsResponseHistory.test.tolerance),1);
    for i = 1:length(obj.optionsResponseHistory.test.tolerance)
        testArgs{i} = sprintf('%s %g %i %i %i',obj.optionsResponseHistory.test.type,...
                                               obj.optionsResponseHistory.test.tolerance(i),...
                                               obj.optionsResponseHistory.test.iterations,...
                                               obj.optionsResponseHistory.test.print,...
                                               obj.optionsResponseHistory.test.normType);
    end

    fprintf(fid,'numberer RCM \n');

    fprintf(fid,'updateRayleighDamping %i %g %i %g\n',...
        obj.damping_ModeA,obj.damping_RatioA,...
        obj.damping_ModeB,obj.damping_RatioB);

    fprintf(fid,'integrator Newmark 0.50 0.25\n');
    fprintf(fid,'analysis VariableTransient \n');

    fprintf(fid,'set currentTime [getTime]\n');
    fprintf(fid,'while { $currentTime < %g } {\n',tend);
    fprintf(fid,'    algorithm %s\n',obj.optionsResponseHistory.algorithm.type{1});
    fprintf(fid,'    test %s\n',testArgs{1});
    fprintf(fid,'    set ok [analyze 1 %g]\n',dt);
    for i = 1:length(testArgs)
        if i == 1; k = 2; else; k = 1; end
        for j = k:length(obj.optionsResponseHistory.algorithm.type)
            fprintf(fid,'    if { $ok != 0 } {\n');
            fprintf(fid,'        algorithm %s\n',obj.optionsResponseHistory.algorithm.type{j});
            fprintf(fid,'        test %s\n',testArgs{i});
            fprintf(fid,'        set ok [analyze 1 %g]\n',dt);
            fprintf(fid,'    }\n');
        end
    end
    fprintf(fid,'    if { $ok != 0 } {\n');
    fprintf(fid,'        exit 2\n');
    fprintf(fid,'    }\n');
    fprintf(fid,'    set currentTime [getTime]\n');
    fprintf(fid,'}\n');

    fprintf(fid,'exit 1 \n');
    fclose(fid);

    % Run OpenSees
    [status, result] = obj.runOpenSees(filename_input);
    results.textOutput = result;
    switch status
        case 1
            results.exitStatus = 'Analysis Successful';
        case 2
            results.exitStatus = 'Analysis Failed';
        otherwise
            fprintf('%s\n',result);
            error('Analysis Failed in Unknown Manner (exit code: %i)',status);
    end

    % Read Results
    temp = dlmread(filename_output_timeSeries);
    results.groundMotion = temp;
    temp = dlmread(filename_output_def);
    results.time = temp(:,1);
    results.totalDrift = temp(:,2:end);
    temp = dlmread(filename_output_vel);
    results.totalVeloc = temp(:,2:end);
    temp = dlmread(filename_output_force);
    results.storyShear = temp(:,2:2:end);

    % Computed Results
    storyDrift = results.totalDrift;
    storyDrift(:,2:end) = storyDrift(:,2:end)-storyDrift(:,1:(end-1));
    results.storyDrift = storyDrift;
    results.roofDrift = results.totalDrift(:,end);
    results.baseShear = results.storyShear(:,1);

    % Clean Folder
    if obj.deleteFilesAfterAnalysis
        delete(filename_input,filename_output_timeSeries,...
            filename_output_def,filename_output_force);
    end
end %function:responseHistory

function results = incrementalDynamicAnalysis(obj,gm_mat,pushoverResults)
    %% incrementalDynamicAnalysis Run an incremental dynamic analysis
    %
    %   IDA = incrementalDynamicAnalysis(obj,gm_mat,pushoverResults) returns the

    if obj.verbose
        fprintf('Running incremental dynamic analysis...\n');
        ida_tic = tic;
    end

    gm = load(gm_mat);
    ground_motions = gm.ground_motions;
    SMT = FEMAP695.SMT(obj.fundamentalPeriod,obj.seismicDesignCategory);
    % ST  = SMT*SF2;
    ST = obj.optionsIDA.ST;
    if ~isempty(obj.SNRT)
        SF1 = FEMAP695.SF1(obj.fundamentalPeriod,obj.seismicDesignCategory,obj.SNRT);
    else
        SF1 = FEMAP695.SF1(obj.fundamentalPeriod,obj.seismicDesignCategory);
    end
    SF2 = ST/SMT;

    maxDriftRatio = cell(obj.optionsIDA.nMotions,1);
    maxDriftRatio(:) = {zeros(1,length(ST))};
    SCT = zeros(obj.optionsIDA.nMotions,1);
    IDA = cell(obj.optionsIDA.nMotions,length(ST));
    IDA(:) = {struct};

    parfor gmIndex = 1:obj.optionsIDA.nMotions
        gmfile = scratchFile(obj,sprintf('acc%s.acc',ground_motions(gmIndex).ID));
        dlmwrite(gmfile,ground_motions(gmIndex).normalized_acceleration*obj.g);

        dt      = ground_motions(gmIndex).dt;
        tend    = max(ground_motions(gmIndex).time) + obj.optionsIDA.tExtra;

        % Vary scale factor
        IDA_part = cell(1,length(ST));
        for sfIndex = 1:length(SF2)
            if obj.verbose
                fprintf('Calculating IDA{%2i, %2i}, gmID = %s, S_T = %5.2f ... ',gmIndex,sfIndex,ground_motions(gmIndex).ID,ST(sfIndex));
            end
            SF = SF1*SF2(sfIndex);
            IDA_part{sfIndex} = responseHistory(obj,gmfile,dt,SF,tend,ground_motions(gmIndex).ID,sfIndex);
            IDA_part{sfIndex}.ST = ST(sfIndex);

            maxDriftRatio{gmIndex}(sfIndex) = max(max(abs(IDA_part{sfIndex}.storyDrift))./obj.storyHeight);

            IDA_part{sfIndex}.E_EQ = energyTest(obj,IDA_part{sfIndex});

            switch IDA_part{sfIndex}.exitStatus
                case 'Analysis Failed'
                    if obj.verbose
                        fprintf('Analysis failed\n');
                    end
                case 'Analysis Successful'
                    if obj.verbose
                        fprintf('Maximum story drift ratio = %5.2f%%\n',maxDriftRatio{gmIndex}(sfIndex)*100);
                    end
            end
            if obj.optionsIDA.shortCircuit && (maxDriftRatio{gmIndex}(sfIndex) > 3*obj.optionsIDA.collapseDriftRatio)
                maxDriftRatio{gmIndex}(sfIndex+1:end) = NaN;
                break
            end
        end
        IDA(gmIndex,:) = IDA_part;

        if any(maxDriftRatio{gmIndex} > obj.optionsIDA.collapseDriftRatio)
            SCT(gmIndex) = ST(find(maxDriftRatio{gmIndex} > obj.optionsIDA.collapseDriftRatio,1));
        else
            SCT(gmIndex) = ST(end);
            warning('Building did not collapse!')
        end

        if obj.deleteFilesAfterAnalysis
            delete(gmfile)
        end
    end

    SCT_hat = median(SCT);
    CMR = SCT_hat/SMT;
    SSF = FEMAP695.SSF(obj.fundamentalPeriod,pushoverResults.periodBasedDuctility,obj.seismicDesignCategory);
    ACMR = SSF*CMR;
    beta_total = FEMAP695.beta_total(obj.optionsIDA.rating_DR,obj.optionsIDA.rating_TD,obj.optionsIDA.rating_MDL,pushoverResults.periodBasedDuctility);
    ACMR20 = FEMAP695.ACMRxx(beta_total,0.2);

    if ACMR < ACMR20
        R_accepted = false;
        R_text = 'unacceptable';
    else
        R_accepted = true;
        R_text = 'acceptable';
    end

    % Annoying struct stuff - need to populate missing fields so that
    % things slot in nicely
    names = fieldnames(IDA{1,1});

    for gmIndex = 1:size(IDA,1)
        for rhIndex = 1:size(IDA,2)
            if isempty(IDA{gmIndex,rhIndex})
                for fIndex = 1:length(names)
                    IDA{gmIndex,rhIndex}.(names{fIndex}) = [];
                end
            end
        end
    end

    % Return results
    results.ACMR = ACMR;
    results.ACMR20 = ACMR20;
    results.beta_total = beta_total;
    results.R_accepted = R_accepted;
    results.SSF = SSF;
    results.SMT = SMT;
    results.SCT_hat = SCT_hat;
    for gmIndex = 1:obj.optionsIDA.nMotions
        results.groundMotion(gmIndex).ID  = ground_motions(gmIndex).ID;
        results.groundMotion(gmIndex).SCT = SCT(gmIndex);
        for rhIndex = 1:length(SF2)
            results.groundMotion(gmIndex).responseHistory(rhIndex) = IDA{gmIndex,rhIndex};
        end
        for rhIndex = 1:length(SF2)     % Two for loops are necessary because adding the maxDriftRatio field breaks pulling the structs out of the cell
            results.groundMotion(gmIndex).responseHistory(rhIndex).maxDriftRatio = maxDriftRatio{gmIndex}(rhIndex);
        end
    end

    % Plot stuff
    obj.plotIDAcurve(results)

    if obj.verbose
        ida_time = toc(ida_tic);
        fprintf('ACMR = %.4g, ACMR20 = %.4g, R is %s\n',ACMR,ACMR20,R_text);
        fprintf('Incremental dynamic analysis took %g seconds.\n',ida_time);
    end

end

function E_EQ = energyTest(obj,results)
% ENERGYTEST

    time = results.time;

    M = obj.storyMass(:);

    relativeVeloc = results.totalVeloc;

    u_dot = relativeVeloc;
    u_ddot_eq = results.groundMotion;

    expression = u_dot*M.*u_ddot_eq;

    E_EQ = -cumtrapz(time,expression);

end

function results = ELFanalysis(obj)
    %% ELFANALYSIS Equivalent Lateral Force procedure (ASCE 7-10)
    %
    %   results = ELFANALYSIS(obj) generates the design story forces,
    %       shears, and allowable story drifts for the information in obj.
    %
    %   The struct results contains the following fields:
    %
    %   seismicResponseCoefficient      ; C_s (Section 12.8.1.1)
    %   baseShear                       ; V (Section 12.8.1)
    %   storyForce                      ; F_x (Section 12.8.3)
    %   storyShear                      ; V_x (Section 12.8.4)
    %   allowableDrift                  ; Delta_a (Table 12.12-1)
    %

    results = struct;

    SDS = FEMAP695.mappedValue('SDS',obj.seismicDesignCategory);
    SD1 = FEMAP695.mappedValue('SD1',obj.seismicDesignCategory);

    approxFundamentalPeriod = 0.02*sum(obj.storyHeight)^0.75;

    if SD1 <= 0.1
        Cu = 1.7;
    elseif SD1 >= 0.4
        Cu = 1.4;
    else
        Cu = interp1([0.1 0.15 0.2 0.3 0.4],[1.7 1.6 1.5 1.4 1.4],SD1);
    end

    if isempty(obj.fundamentalPeriod)
        obj.fundamentalPeriod = 0.02*sum(obj.storyHeight)^0.75;
    elseif obj.fundamentalPeriod > Cu*approxFundamentalPeriod
        obj.fundamentalPeriod = Cu*approxFundamentalPeriod;
    end

    maxSeismicResponseCoefficient = SD1/(obj.fundamentalPeriod*obj.respModCoeff/obj.impFactor);
    results.seismicResponseCoefficient = min(SDS/(obj.respModCoeff/obj.impFactor),maxSeismicResponseCoefficient);

    seismicWeight = sum(obj.storyMass)*obj.g;
    results.baseShear = seismicWeight*results.seismicResponseCoefficient;

    if obj.fundamentalPeriod <= 0.5
        k = 1;
    elseif obj.fundamentalPeriod >= 2.5
        k = 2;
    else
        k = interp1([0.5 2.5],[1 2],obj.fundamentalPeriod);
    end

    verticalDistributionFactor = (obj.storyMass*obj.g .* cumsum(obj.storyHeight).^k)/sum(obj.storyMass*obj.g .* cumsum(obj.storyHeight).^k);

    results.storyForce = verticalDistributionFactor*results.baseShear;
    results.storyShear = zeros(1,obj.nStories);
    for i = 1:obj.nStories
        results.storyShear(i) = sum(results.storyForce(i:end));
    end

    results.allowableDrift = 0.020*obj.storyHeight;

end %function:ELFanalysis

function spring = springDesign(obj,analysisResults,springGivens)
    %% Story spring design

    spring = struct;

    designStiffness = springGivens.stiffnessSafety*obj.deflAmplFact*analysisResults.storyShear./(obj.impFactor*analysisResults.allowableDrift);

    designStrength  = springGivens.strengthSafety*obj.overstrengthFactor*analysisResults.storyShear;

    if springGivens.enforceMinimumStiffness
        for i = 2:length(designStiffness)
            if designStiffness(i) < springGivens.minimumRatio*designStiffness(i-1)
                designStiffness(i) = springGivens.minimumRatio*designStiffness(i-1);
            end
        end
    end
    if springGivens.enforceMinimumStrength
        for i = 2:length(designStrength)
            if designStrength(i) < springGivens.minimumRatio*designStrength(i-1)
                designStrength(i) = springGivens.minimumRatio*designStrength(i-1);
            end
        end
    end

    for i = 1:obj.nStories
        if springGivens.includePDelta
            Px = sum(obj.storyMass(i:end))*obj.g;
            theta = (Px*analysisResults.allowableDrift(i)*obj.impFactor)/(analysisResults.storyShear(i)*obj.storyHeight(i)*obj.deflAmplFact);
            theta_max = min(0.5/obj.deflAmplFact,0.25);
            theta = min(theta,theta_max);
        else
            theta = 0;
        end
        spring(i).K0       = (1-theta)*designStiffness(i);            % elastic stiffness
        spring(i).as       = springGivens.as - theta;               % strain hardening ratio
        spring(i).ad       = springGivens.ad + theta;               % strain hardening ratio
        spring(i).Lambda_S = springGivens.Lambda_S;         % Cyclic deterioration parameter - strength
        spring(i).Lambda_K = springGivens.Lambda_K;         % Cyclic deterioration parameter - stiffness
        spring(i).c_S      = springGivens.c_S;              % rate of deterioration - strength
        spring(i).c_K      = springGivens.c_K;              % rate of deterioration - stiffness
        spring(i).Res      = springGivens.Res;              % residual strength ratio
        spring(i).D        = springGivens.D;                % rate of cyclic deterioration
        spring(i).nFactor  = springGivens.nFactor;          % elastic stiffness amplification factor
        spring(i).theta    = theta;

        spring(i).V_c = (1-theta)*designStrength(i);                  % strength at capping
        spring(i).V_y = springGivens.C_yc*spring(i).V_c;    % effective yield strength

        spring(i).defl_y  = spring(i).V_y./spring(i).K0;                                                    % deflection at yield
        spring(i).defl_p  = (spring(i).V_c-spring(i).V_y)./((spring(i).as+theta)*spring(i).K0);             % pre-capping deflection
        spring(i).defl_pc = spring(i).V_c/(spring(i).ad*spring(i).K0);                                      % post-capping deflection
        spring(i).defl_u  = springGivens.C_upc*(spring(i).defl_y + spring(i).defl_p + spring(i).defl_pc);   % ultimate deflection capacity

        spring(i).definition = bilinearMaterialDefinition(i,spring(i));
    end

end %function:springDesign

%% Plot Functions

function fig = plotSampleResponse(obj,results,varargin)
    %% PLOTSAMPLERESPONSE Plot selected time history results
    %
    %   PLOTSAMPLERESPONSE(results) plots the ground motion and the
    %       total roof drift as two subplots in a single figure.
    %
    %   PLOTSAMPLERESPONSE(results,'story',stories) plots the ground
    %       motion and the story drift of the stories specified in the
    %       vector stories.
    %
    if nargin > 2
        plotRoofDrift = false;
        for arg = 1:length(varargin)
            if ischar(varargin{arg})
                switch lower(varargin{arg})
                    case 'roof'
                        plotRoofDrift = true;
                    case 'story'
                        assert(isvector(varargin{arg+1}) && isnumeric(varargin{arg+1}),'stories should be a vector')
                        stories = varargin{arg+1};
                        plotStoryDrift = true;
                    otherwise
                        error('Invalid argument');
                end
            end
        end
    else
        plotRoofDrift = true;
        plotStoryDrift = false;
    end

    if plotStoryDrift && plotRoofDrift
        nPlots = 3;
    else
        nPlots = 2;
    end

    fig = figure;
    pos = fig.Position;
    fig.Position = get(groot,'Screensize'); % Maximizing the figure window when drawing will reduce whitespace around plots

    subplot(nPlots,1,1)
    plot(results.time,results.groundMotion,'-')
    grid on
    grid minor
    yl = ylim;
    ylim([-max(abs(yl)),max(abs(yl))])
    xlabel(sprintf('Time (%s)',obj.units.time))
    ylabel(sprintf('Acceleration (%s/%s^2)',obj.units.length,obj.units.time))
    if isfield(results,'gmID') && isfield(results,'ST')
        titleText = sprintf('Input Ground Motion (GM: %s, S_T: %gg)',results.gmID,results.ST);
    elseif isfield(results,'gmID')
        titleText = sprintf('Input Ground Motion (GM: %s, SF: %g)',results.gmID,results.SF);
    else
        titleText = sprintf('Input Ground Motion (SF: %g)',results.SF);
    end
    title(titleText)

    if plotRoofDrift
        subplot(nPlots,1,2)
        plot(results.time,results.roofDrift,'-')
        grid on
        grid minor
        yl = ylim;
        ylim([-max(abs(yl)),max(abs(yl))])
        xlabel(sprintf('Time (%s)',obj.units.time))
        ylabel(sprintf('Drift (%s)',obj.units.length))
        title('Total Roof Drift')
    end

    if plotStoryDrift
        subplot(nPlots,1,nPlots)
        hold on
        legendentries = cell(length(stories),1);
        for plotIndex = 1:length(stories)
            plot(results.time,results.storyDrift(:,stories(plotIndex)))
            legendentries{plotIndex} = sprintf('Story %i',stories(plotIndex));
        end
        grid on
        grid minor
        yl = ylim;
        ylim([-max(abs(yl)),max(abs(yl))])
        xlabel(sprintf('Time (%s)',obj.units.time))
        ylabel(sprintf('Drift (%s)',obj.units.length))
        legend(legendentries)
        title('Story Drift')
    end
    fig.Position = pos;

    if nargout == 0
        clear fig
    end

end %function:plotSampleResponse

function animateResponseHistory(obj,results,dt)
    %% ANIMATERESPONSEHISTORY Animate a given response history
    %
    %   ANIMATERESPONSEHISTORY(obj,results) is the default usage.
    %
    %   ANIMATERESPONSEHISTORY(obj,results,dt) allows for overriding the
    %       timestep used. This option must be used to allow for
    %       pushover analyses, as those contain no time results and time
    %       is arbitrary with them anyways.
    %

    if nargin == 2
        if isfield(results,'time')
            dt = max(diff(results.time));
        else
            error('Undefined timestep.')
        end
    end

    cumHeights = cumsum(obj.storyHeight);

    figure

    grid on
    grid minor

    xMax = max(max(abs(results.totalDrift)));
    yMax = sum(obj.storyHeight) + obj.storyHeight(1);

    axis([-xMax xMax 0 yMax]);
    ax = gca;
    ax.YTick = cumHeights;

    ylabel(sprintf('Height (%s)',obj.units.length))
    xlabel(sprintf('Drift (%s)',obj.units.length))

    h = animatedline([0 results.totalDrift(1,:)],[0 cumHeights],'Marker','*');
    t = text(2/3*xMax,1/5*yMax,'Time: 0.0s');

    for i = 1:size(results.totalDrift,1)
        displayText = sprintf('Time: %4.1fs',i*dt);
        delete(t)
        clearpoints(h)
        addpoints(h,[0 results.totalDrift(i,:)],[0 cumHeights])
        t = text(ax,2/3*xMax,1/5*yMax,displayText);
        drawnow
    end

end %function:animateResponseHistory

function fig = plotIDAcurve(obj,results)
    %% plotIDAcurve Plot the incremental dynamic analysis curve
    %
    %

    nMotions   = length(results.groundMotion);
    nHistories = length(results.groundMotion(1).responseHistory);

    fig = figure;
    hold on
    IDA_colors = parula(nMotions);
    legendentries = cell(nMotions,1);
    for gmIndex = 1:nMotions
        drifts = zeros(1,nHistories);
        ST     = zeros(1,nHistories);
        for rhIndex = 1:nHistories
            if isnan(results.groundMotion(gmIndex).responseHistory(rhIndex).maxDriftRatio)
                drifts(rhIndex) = NaN;
                ST(rhIndex)     = NaN;
            else
                drifts(rhIndex) = results.groundMotion(gmIndex).responseHistory(rhIndex).maxDriftRatio;
                ST(rhIndex)     = results.groundMotion(gmIndex).responseHistory(rhIndex).ST;
            end
        end
        goodDrifts = ~isnan(drifts);
        plot([0 drifts(goodDrifts)*100],[0 ST(goodDrifts)],'o-','Color',IDA_colors(gmIndex,:))
        legendentries{gmIndex} = results.groundMotion(gmIndex).ID;
    end
    plot(xlim,[results.SCT_hat,results.SCT_hat],'k--');
    plot(xlim,[results.SMT,results.SMT],'b--');
    legendentries{end+1} = '$\hat{S}_{CT}$';
    legendentries{end+1} = '$S_{MT}$';

    grid on
    xlim([0 3*obj.optionsIDA.collapseDriftRatio*100])
    xlabel('Maximum story drift ratio (%)')
    ylabel('Ground motion intensity, S_T (g)')
    leg = legend(legendentries);
    leg.Interpreter = 'latex';

    if nargout == 0
        clear fig
    end

end %function:plotIDAcurve

function fig = plotStoryDriftAndShear(obj,results,stories)
    %% plotStoryDriftAndShear Plot story shear against story drift.
    %
    %
    %

    if nargin == 2
        stories = 1;
    end

    fig = figure;
    hold on

    legendentries = cell(1,length(stories));
    for stIndex = 1:length(stories)
        plot(results.storyDrift(:,stories(stIndex)),results.storyShear(:,stories(stIndex)))
        legendentries{stIndex} = sprintf('Story %i',stories(stIndex));
    end

    legend(legendentries)
    xlabel(sprintf('Story drift (%s)',obj.units.length))
    ylabel(sprintf('Story shear (%s)',obj.units.force))
    grid on
    grid minor

    if nargout == 0
        clear fig
    end

end %function:plotStoryDriftAndShear

function fig = plotBackboneCurves(obj,spring)
    fig = figure;
    hold on
    endpoint = zeros(obj.nStories,1);
    legendentries = cell(obj.nStories,1);
    for i = 1:obj.nStories
        materialDefinition = spring(i).definition;
        matTagLoc = strfind(materialDefinition,num2str(i));
        materialDefinition(matTagLoc(1)) = '1';
        endpoint(i) = spring(i).defl_y + spring(i).defl_p + spring(i).defl_pc;
        anaobj = UniaxialMaterialAnalysis(materialDefinition);
        rateType    = 'StrainRate';
        rateValue   = 0.001;
        backbone = anaobj.runAnalysis([0 endpoint(i)],rateType,rateValue,i);
        legendentries{i} = sprintf('Story %i',i);
        plot(backbone.disp,backbone.force)
    end
    xlim([0 1.1*max(endpoint)])
    title('Backbone curves')
    xlabel(sprintf('Deflection (%s)',obj.units.length))
    ylabel(sprintf('Force (%s)',obj.units.force))
    legend(legendentries)
    grid on
    if nargout == 0
        clear fig
    end
end

end %methods
end %classdef:mdofShearBuilding2d


function tf = isvectorsize(v,n)
    s = size(v);
    tf = isequal(s,[n 1]) || isequal(s,[1 n]);
end %function:isvectorsize

function writeFunction_updateRayleighDamping(fid)
    fprintf(fid,'proc updateRayleighDamping { modeA ratioA modeB ratioB } {\n');
    fprintf(fid,'    # ###################################################################\n');
    fprintf(fid,'    # updateRayleighDamping $modeA $ratioA $modeB $ratioB\n');
    fprintf(fid,'    # ###################################################################\n');
    fprintf(fid,'    # Runs an eigenvalue analysis and set proportional damping based on\n');
    fprintf(fid,'    # the current state of the structure\n');
    fprintf(fid,'    #\n');
    fprintf(fid,'    # Input Parameters:\n');
    fprintf(fid,'    # modeA, modeB - modes that will have prescribed damping ratios\n');
    fprintf(fid,'    # ratioA, ratioB - damping ratios prescribed at the specified modes\n');
    fprintf(fid,'\n');
    fprintf(fid,'    # Get natural frequencies at the desired modes\n');
    fprintf(fid,'    if { $modeA > $modeB } {\n');
    fprintf(fid,'        set maxMode $modeA\n');
    fprintf(fid,'    } else {\n');
    fprintf(fid,'        set maxMode $modeB\n');
    fprintf(fid,'    }\n');
    fprintf(fid,'\n');
    fprintf(fid,'    set eigs    [eigen -fullGenLapack $maxMode]\n');
    fprintf(fid,'    set freqA   [expr sqrt([lindex $eigs [expr $modeA-1]])]\n');
    fprintf(fid,'    set freqB   [expr sqrt([lindex $eigs [expr $modeB-1]])]\n');
    fprintf(fid,'\n');
    fprintf(fid,'    # Compute the damping factors\n');
    fprintf(fid,'    set tempVal [expr 2.0/($freqA*$freqA-$freqB*$freqB)]\n');
    fprintf(fid,'    set aM      [expr $tempVal*$freqA*$freqB*($ratioB*$freqA-$ratioA*$freqB)]\n');
    fprintf(fid,'    set aK      [expr $tempVal*($ratioA*$freqA-$ratioB*$freqB)]\n');
    fprintf(fid,'\n');
    fprintf(fid,'    # Set the damping\n');
    fprintf(fid,'    rayleigh $aM 0.0 0.0 $aK\n');
    fprintf(fid,'}\n');
end %function:writeFunction_updateRayleighDamping

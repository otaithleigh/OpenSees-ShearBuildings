% test_ELFdesign.m
% Units: kslug, kip, ft, sec

tic
clear; close all; clc;
addpath('../UniaxialMaterialAnalysis');

%% Define Building
nStories = 3;
bldg = mdofShearBuilding2d(nStories);
bldg.echoOpenSeesOutput = false;
bldg.deleteFilesAfterAnalysis = true;
verbose = true;                                 % Verbose output (bool)
bldg.g = 32.2;                                  % Acceleration due to gravity (ft/s^2)

bldg.storyHeight = [20 15 15];                  % Story heights (ft)
storyDL = [0.080 0.080 0.030];                  % Story dead loads (ksf)
storyArea = 90*90*ones(1,nStories);             % Story areas (ft^2)
bldg.storyMass = (storyDL .* storyArea)/bldg.g; % Story masses (kslug)

bldg.seismicDesignCategory = 'Dmax';
bldg.responseModificationCoefficient = 8;
bldg.deflectionAmplificationFactor = 5.5;
bldg.overstrengthFactor = 3;
bldg.importanceFactor = 1;

%% Analysis Options

% Equivalent lateral force options
iterate = false;             % Select whether to do iteration
iterOption = 'period';      % Variable to use for convergence: 'period' or 'overstrength'

minPeriodDiff = 1e-3;       % Tolerance for period convergence option

% Incremental dynamic analysis options
nMotions = 4;                                   % Number of ground motions to analyze
SF2 = [0:.25:1.5, 2:0.5:6, 6.75:0.75:9, 10:12]; % Scale factors to use for each IDA curve

%% Design building
resultsELF = bldg.ELFdesign();

iterating = true;
while iterating == true
    %% Define springs
    spring = bldg.springDesign(resultsELF,springGivens);

    bldg.storySpringDefinition = spring.definition;

    if ~iterate
        iterating = false;
    end
    if iterate
        switch lower(iterOption)
            case 'period'
                eigenvals = bldg.eigenvalues();
                calculatedPeriod = (eigenvals(1)/(2*pi))^-1;
                prevDiff = periodDiff;
                periodDiff = bldg.fundamentalPeriod - calculatedPeriod;
                bldg.fundamentalPeriod = calculatedPeriod;
                resultsELF = bldg.ELFdesign;
                if prevDiff == periodDiff
                    iterating = false;
                end
            case 'overstrength'
                fprintf('Not yet implemented')
                iterating = false;
        end
    end
end

%% Incremental Dynamic Analysis
load('ground_motions.mat');
SMT = FEMAP695_SMT(bldg.fundamentalPeriod,bldg.seismicDesignCategory);
ST  = SMT*SF2;
figure
hold on
legendentries = cell(nMotions,1);
results = cell(nMotions,length(SF2));
for i = 1:nMotions %length(ground_motions)
    gmfile = bldg.scratchFile(sprintf('acc%s.acc',ground_motions(i).ID));
    gmfid = fopen(gmfile,'w+');
    for k = 1:ground_motions(i).numPoints
        fprintf(gmfid,'%f\n',ground_motions(i).normalized_acceleration(k)*bldg.g);
    end
    fclose(gmfid);
    dt      = ground_motions(i).dt;
    SF1     = FEMAP695_SF1(bldg.fundamentalPeriod,bldg.seismicDesignCategory);
    tend    = max(ground_motions(i).time) + 5;

    % Vary scale factor

    maxDrift = zeros(length(SF2),1);
    parfor j = 1:length(SF2)
        if verbose
            fprintf('Calculating IDA point for %s, SF2 = %g\n',ground_motions(i).ID,SF2(j));
        end
        SF = SF1*SF2(j);
        results{i,j} = bldg.responseHistory(gmfile,dt,SF,tend,ground_motions(i).ID,j);
        maxDrift(j) = max(max(abs(results{i,j}.storyDrift))./bldg.storyHeight);
    end

    plot(maxDrift,ST,'o-')
    legendentries{i} = ground_motions(i).ID;

    if bldg.deleteFilesAfterAnalysis
        delete(gmfile)
    end
end


grid on
xlabel('Maximum story drift ratio')
ylabel('Ground motion intensity, S_T (g)')
legend(legendentries)

% Plot sample response history
plotSampleResponse(results{1,5})

% Plot backbone curves
figure
hold on
backbone_ax = cell(nStories,1);
for i = 1:nStories
    backbone_ax{i} = subplot(nStories,1,i);
    materialDefinition = bldg.storySpringDefinition{i};
    matTagLoc = strfind(materialDefinition,num2str(i));
    materialDefinition(matTagLoc(1)) = '1';
    plotBackboneCurve(materialDefinition,defl_u(i),false)
    title(sprintf('Backbone curve for story %i',i))
    xlabel('Deflection (ft)')
    ylabel('Force (kip)')
    grid on
end

rmpath('../UniaxialMaterialAnalysis');

toc

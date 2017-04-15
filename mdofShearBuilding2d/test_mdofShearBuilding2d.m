clear; close all; clc;

%% Define Building
nStories = 4;
bldg = mdofShearBuilding2d(nStories);
bldg.echoOpenSeesOutput = true;
bldg.deleteFilesAfterAnalysis = false;
bldg.pushover_stepSize = 0.001;
bldg.pushover_maxDrift = 6.0;

bldg.storyMass = [2 1 1 1];

% bldg.storySpringDefinition = {...
%     'uniaxialMaterial Hardening 1 100 100 10 0'
%     'uniaxialMaterial Hardening 2 150 80 10.1 0'
%     'uniaxialMaterial Hardening 3 100 100 10 0'
%     'uniaxialMaterial Hardening 4 150 80 10.1 0'};

load('uniaxialMaterial.mat');

bldg.storySpringDefinition = {
    materialDefinition1
    'uniaxialMaterial Elastic 2 1000'
    'uniaxialMaterial Elastic 3 1000'
    'uniaxialMaterial Elastic 4 1000'
};


%% Pushover Analysis
% results1 = bldg.pushover([0.1 0.3 0.3 0.3]','TargetDrift',10);
results1 = bldg.pushover(10*[0.1 0.3 0.3 0.3]','TargetPostPeakRatio',0.75);

figure
plot(results1.roofDrift,results1.baseShear,'-')
grid on
grid minor
xlabel('Roof drift')
ylabel('Base shear')
title('P-Delta for Roof')

%% Deflected shape - Pushover
figure
plot([0 results1.totalDrift(end,:)],0:nStories,'*-')
grid on
grid minor
ylabel('Story')
xlabel('Total drift')
title('Deflected Shape - Pushover Analysis')

%% Response History Analysis
gmfile  = 'test.acc';
dt      = 0.01;
SF      = 200.0;
tend    = 50.0;
results2 = bldg.responseHistory(gmfile,dt,SF,tend);

figure
subplot(211)
plot(results2.time,results2.groundMotion,'-')
grid on
grid minor
xlabel('Time (s)')
ylabel('Acceleration (g)')
title('Input Ground Motion')

subplot(212)
plot(results2.time,results2.roofDrift,'-')
grid on
grid minor
axisLimits = axis;
axis([axisLimits(1:2),-max(abs(axisLimits(3:4))),max(abs(axisLimits(3:4)))])
xlabel('Time (s)')
ylabel('Roof drift')
title('Roof Drift')
%
% %% Deflected shape - Response History at maximum displacement
%
% absMax = max(max(abs(results2.totalDrift)));
% absMaxIndex = abs(results2.totalDrift) == absMax;
% [rowMax,~] = find(absMaxIndex);
%
% figure
% plot([0 results2.totalDrift(rowMax,:)],0:nStories,'*-')
% grid on
% grid minor
% ylabel('Story')
% xlabel('Total drift')
% title('Deflected Shape - Maximum Response')
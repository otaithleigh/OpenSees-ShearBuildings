function plotBackboneCurve(materialDefinition,theta_u,newfig)

anaobj = UniaxialMaterialAnalysis(materialDefinition);

rateType    = 'StrainRate';
rateValue   = 0.01;
results_pos_env = anaobj.runAnalysis([0 1.1*theta_u],rateType,rateValue);

if newfig
    figure
end
plot(results_pos_env.disp,results_pos_env.force,'k--')

end

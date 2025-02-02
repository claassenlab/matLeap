function mlPrepareModel( modelDir, mexName, sbmlModel, opts )
[ S, Sed, Prop, ReacDep ] = mlSBML2StoichProp(sbmlModel, true, true);
% Model definition
mlGenModelDefh(fullfile(modelDir, 'model_def.h'), length(sbmlModel.species), length(sbmlModel.reaction), length(sbmlModel.parameter));
% StoichiometrixMatrix
mlGenStoichMatrixCCode(S, Sed, fullfile(modelDir, 'computeStoichiometrixMatrix.cpp'));
% Jacobian @f/@x
symProp = cell2sym(Prop');
symX = sym({sbmlModel.species.id});
dadx = jacobian(symProp, symX);
syms tau
J = eye(length(symX)) - tau/2*S*dadx;
if (opts.SYM_JAC)
    J = inv(J);
    jFName = 'inverseJ';
else
    jFName = 'J';
end
snippet = ccode(J);
mlGenCCode(jFName, snippet, {{sbmlModel.species.id},{sbmlModel.parameter.id},{'tau'}}, 'J', size(J), true, false, false, fullfile(modelDir, [jFName '.cpp']));
% Propensity function (switch, depending on last Reaction)
strSwitch = sprintf('\n\tswitch(lastReacIdx) {');
strSwitch = sprintf('%s\n\tcase 0:', strSwitch);
strSwitch = sprintf('%s\n\t%s\n\tbreak;', strSwitch, strrep(ccode(symProp),'symProp','p_f'));
for rIdx = 1:size(ReacDep,1)
    strSwitch = sprintf('%s\n\tcase %d:', strSwitch, rIdx);
    curSymProp = symProp;
    curSymProp(setdiff(1:size(ReacDep,1),ReacDep{rIdx})) = 0;
    snippet = strrep(ccode(curSymProp),'curSymProp','p_f');
    strSwitch = sprintf('%s\n\t%s', strSwitch, snippet);
    strSwitch = sprintf('%s\n\tbreak;', strSwitch);
end
strSwitch = sprintf('%s\n\t}', strSwitch);
mlGenCCode('computePropensities', strSwitch, {{sbmlModel.species.id},{sbmlModel.parameter.id}}, 'f', length(sbmlModel.reaction), true, true, true, fullfile(modelDir, 'computePropensities.cpp'));
mlInstallDir = getenv('matLeap1_InstallDir');
if (isempty(mlInstallDir))
    error('matLeap installdir not found. Please run init.m in matLeap''s root directory.');
end
cppSrcPath = fullfile(mlInstallDir, 'src');
mexFuncPath = fullfile(modelDir, [mexName '.' mexext]);

tmp = dir([modelDir '/*.cpp']);
tmp = {tmp.name};
modelFiles = cellfun(@(s) fullfile(modelDir, s), tmp, 'UniformOutput', false);
tmp = dir([cppSrcPath '/*.cpp']);
tmp = {tmp.name};
matLeapFiles = cellfun(@(s) fullfile(cppSrcPath, s), tmp, 'UniformOutput', false);

mexCmd = ['mex ' strjoin([modelFiles, matLeapFiles]) ' -I' modelDir '/ -I. -Iboost/ -DMEX -O '];

if isunix
     mexCmd = [mexCmd '-lut -output ' mexFuncPath];
else
   % windows x32 or x64
   if strcmp(computer, 'PCWIN')
       winStr = 'win32';
   else
       winStr = 'win64';
   end
   
   % find libut.lib
   compilerConfiguration = mex.getCompilerConfigurations('C++','Selected');
   
   if strcmp(compilerConfiguration(1).Manufacturer, 'Microsoft')
       libDir = 'microsoft';
   else
       error('Only microsoft compiler supported')
   end
   
   mexCmd = [mexCmd '"' matlabroot '/extern/lib/' winStr '/' libDir '/libut.lib" -output ' mexFuncPath];
%    mexCmd = [mexCmd matlabroot '/extern/lib/win32/lcc/libut.lib -output ' mexFuncPath];
end
if (opts.SYM_JAC)
    mexCmd = [mexCmd ' -DINVJ'];
end

eval(mexCmd);
end

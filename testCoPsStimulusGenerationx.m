function tests = testCoPsStimulusGenerationx
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(mfilename('fullpath'));
folder = tempname; mkdir(folder);
testCase.TestData.folder = folder;
testCase.TestData.repoRoot = repoRoot;
testCase.TestData.originalPath = path;
fixture = load(fullfile(repoRoot,'test_data','stimgen','reference.mat'));
testCase.TestData.reference = fixture.reference;
testCase.TestData.settings = fixture.settings;
inputRoot = fullfile(folder,'inputs');
for kind = {'faces_scrambled_raw','objects_scrambled_raw'}
    target = fullfile(inputRoot,kind{1}); mkdir(target);
    copyfile(fullfile(repoRoot,'test_data','stimgen','template.png'), ...
        fullfile(target,'fn_0001_sample_01.png'));
end
testCase.TestData.inputRoot = inputRoot;
% Hostile names simulate an old synthesis installation on the MATLAB path.
shadow = fullfile(folder,'shadow'); mkdir(shadow);
for name = {'gauss_mask','textureAnalysis_wz','textureSynthesis_wz','pointOp','clip'}
    fid = fopen(fullfile(shadow,[name{1} '.m']),'w');
    fprintf(fid,'function varargout=%s(varargin)\nerror(''StimGenTest:Shadow'',''Wrong helper resolved.'');\nend\n',name{1});
    fclose(fid);
end
testCase.TestData.shadow = shadow;
addpath(repoRoot,'-begin'); addpath(shadow,'-begin');
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
folder = testCase.TestData.folder;
assert(strcmp(fileparts(folder),fileparts(tempname)), ...
    'Refusing to remove a directory outside the temporary folder.');
rmdir(folder,'s');
end

function testMethodOneMatchesOriginalNativeGenerator(testCase)
verifyMethod(testCase,1);
end

function testMethodTwoMatchesOriginalNativeGenerator(testCase)
verifyMethod(testCase,2);
end

function testMethodThreeMatchesOriginalNativeGenerator(testCase)
verifyMethod(testCase,3);
end

function testSharedMaskPreservesTaskAndGeneratorWidthConventions(testCase)
image = zeros(101);
task = copsstim.gaussMask(image,51,51,30);
generator = copsstim.gaussMask(image,51,51,30,30);
verifyEqual(testCase,task(51,51),1);
verifyEqual(testCase,task(51,61),exp(-0.5),'AbsTol',eps);
verifyEqual(testCase,generator(51,81),exp(-0.5),'AbsTol',eps);
verifyGreaterThan(testCase,generator(51,61),task(51,61));
% Exercise the retained public API from the repository, where it lives.
original = pwd; cd(testCase.TestData.repoRoot);
cleanup = onCleanup(@() cd(original)); %#ok<NASGU>
verifyEqual(testCase,gauss_mask(image,51,51,30),task);
verifyEqual(testCase,gauss_mask(image,51,51,30,30),generator);
end

function testGeneratedBankPassesTaskLoaderValidation(testCase)
out = generate(testCase,3); item = out.sessions(1).images(1);
ex.stim.seq = {item.folder};
ex.exp.CoPs.graph = struct('background_noise_lvl',[-1 0 1],'full_as_background',false);
ex.exp.CoPs.ctl.coherence = [1 0.5];
info = validateCoPsStimulusSelection(ex);
verifyEqual(testCase,info.nActiveTrials,1);
verifyEqual(testCase,double(info.nUniqueRequirements),6);
verifyEqual(testCase,info.nUniqueStimulusFolders,1);
end

function testManifestRecordsSettingsAndSelectedSource(testCase)
out = generate(testCase,1);
saved = load(fullfile(out.sessions(1).daily_dir,'generation_manifest.mat'));
verifyEqual(testCase,saved.manifest.settings.rng_seed,42);
verifyEqual(testCase,saved.manifest.settings.method,1);
verifyEqual(testCase,saved.manifest.session.rng_seed,out.sessions(1).rng_seed);
verifyEqual(testCase,saved.manifest.session.images(1).sourcePath, ...
    fullfile(testCase.TestData.inputRoot,'faces_scrambled_raw','fn_0001_sample_01.png'));
end

function testExplicitMixedSourceSelectionWorks(testCase)
opts = options(testCase,1); opts.Ntp = 1;
selection = ["face_fn_0001_sample_01","object_fn_0001_sample_01"];
out = invoke(testCase,'ab','both',selection,opts);
images = out.sessions(1).images;
verifyEqual(testCase,{images.sourceType},{'face','object'});
verifyTrue(testCase,endsWith(out.sessions(1).daily_dir,'ab_reference_stim1'));
verifyTrue(testCase,isfile(fullfile(images(2).fullFolder,'full_0001.mat')));
end

function testEnvironmentSourceRootAndRepositoryOutputDefault(testCase)
previous = getenv('COPS_STIM_SOURCE_ROOT');
setenv('COPS_STIM_SOURCE_ROOT',testCase.TestData.inputRoot);
cleanup = onCleanup(@() setenv('COPS_STIM_SOURCE_ROOT',previous)); %#ok<NASGU>
opts = options(testCase,1);
opts = rmfield(opts,{'source_root','output_root'});
opts.save_bool = false; opts.Ntp = 0;
out = invoke(testCase,'','face',1,opts);
verifyEqual(testCase,out.source_dir,fullfile(testCase.TestData.inputRoot,'faces_scrambled_raw'));
verifyEqual(testCase,out.options.output_root,fullfile(testCase.TestData.repoRoot,'stimuli'));
end

function testMissingSourceAndUnknownOptionGiveUsefulErrors(testCase)
opts = options(testCase,1);
opts.source_root = fullfile(testCase.TestData.folder,'missing');
verifyError(testCase,@() invoke(testCase,'','face',1,opts),'genDailyStimCorey:SourceFolderMissing');
opts = options(testCase,1); opts.typo = 1;
verifyError(testCase,@() invoke(testCase,'','face',1,opts),'genDailyStimCorey:UnknownOption');
end

function testDependencyClosureStaysInsideRepository(testCase)
[files,products] = matlab.codetools.requiredFilesAndProducts( ...
    fullfile(testCase.TestData.repoRoot,'genDailyStimCorey.m'));
allowed = startsWith(files,[testCase.TestData.repoRoot filesep],'IgnoreCase',ispc) | ...
    startsWith(files,[matlabroot filesep],'IgnoreCase',ispc);
verifyTrue(testCase,all(allowed),strjoin(files(~allowed),newline));
verifyEqual(testCase,{products.Name},{'MATLAB'});
end

function verifyMethod(testCase,method)
out = generate(testCase,method); item = out.sessions(1).images(1);
expected = testCase.TestData.reference(method);
for frame=1:2
    full = load(fullfile(item.fullFolder,sprintf('full_%04d.mat',frame)));
    scramble = load(fullfile(item.scrambleFolder,sprintf('scramble_%04d.mat',frame)));
    verifyEqual(testCase,full.full_tp,expected.full(:,:,frame),'AbsTol',1e-8);
    verifyEqual(testCase,scramble.scramble_tp,expected.scramble(:,:,frame),'AbsTol',1e-8);
    if method==3
        mix = load(fullfile(item.noiseFolder,'mix50',sprintf('mix50_%04d.mat',frame)));
        verifyEqual(testCase,mix.mix_tpi,expected.mix50(:,:,frame),'AbsTol',1e-8);
    end
end
full = load(fullfile(item.folder,'full_as_target.mat'));
scramble = load(fullfile(item.folder,'scr_as_target.mat'));
verifyEqual(testCase,full.full_is_target,expected.full_as_target,'AbsTol',1e-10);
verifyEqual(testCase,scramble.scr_is_target,expected.scr_as_target,'AbsTol',1e-10);
end

function out = generate(testCase,method)
out = invoke(testCase,'','face',1,options(testCase,method));
end

function opts = options(testCase,method)
opts = testCase.TestData.settings;
opts.method = method;
opts.source_root = testCase.TestData.inputRoot;
opts.output_root = tempname(testCase.TestData.folder);
opts.add_paths = true; % accepted legacy flag must leave the path unchanged
end

function out = invoke(testCase,varargin)
original = pwd; cd(testCase.TestData.shadow);
cleanup = onCleanup(@() cd(original)); %#ok<NASGU>
pathBefore = path;
evalc('out=genDailyStimCorey(varargin{:});');
assert(strcmp(pathBefore,path),'StimGenTest:PathChanged','Generator changed the MATLAB path.');
end

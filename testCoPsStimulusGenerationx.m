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

function testLocalModeUsesBundledDefaultsDespiteEnvironment(testCase)
previous = getenv('COPS_STIM_SOURCE_ROOT');
setenv('COPS_STIM_SOURCE_ROOT',fullfile(testCase.TestData.folder,'missing_network_source'));
cleanup = onCleanup(@() setenv('COPS_STIM_SOURCE_ROOT',previous)); %#ok<NASGU>
opts = struct('sessions',1,'Ntp',0,'Niter',1,'save_bool',false,'rng_seed',42, ...
    'date_tag',['local_defaults_' char(java.util.UUID.randomUUID())]);
out = invoke(testCase,' LOCAL ',opts);
verifyTrue(testCase,out.localMode);
verifyEqual(testCase,out.options.source_root,fullfile(testCase.TestData.repoRoot,'stimulus_sources'));
verifyEqual(testCase,out.options.output_root,fullfile(testCase.TestData.repoRoot,'stimuli'));
verifyEqual(testCase,out.stimType,'face');
verifyNumElements(testCase,out.sessions(1).images,5);
verifyNumElements(testCase,unique([out.sessions(1).images.imageId]),5);
end

function testLocalModeGeneratesARealBundledBank(testCase)
opts = options(testCase,1); opts = rmfield(opts,'source_root'); opts.Ntp = 1;
out = invoke(testCase,'local','face',1,opts);
item = out.sessions(1).images(1);
verifyTrue(testCase,out.localMode);
verifyTrue(testCase,startsWith(item.sourcePath,fullfile(testCase.TestData.repoRoot,'stimulus_sources')));
verifyTrue(testCase,endsWith(out.sessions(1).daily_dir,'reference_stim1'));
full = load(fullfile(item.fullFolder,'full_0001.mat'));
source = imread(item.sourcePath);
verifyEqual(testCase,size(full.full_tp),size(source,[1 2]));
verifyTrue(testCase,all(isfinite(full.full_tp),'all'));
saved = load(fullfile(out.sessions(1).daily_dir,'generation_manifest.mat'));
verifyTrue(testCase,saved.manifest.localMode);
ex.stim.seq = {item.folder};
ex.exp.CoPs.graph = struct('background_noise_lvl',[-1 0 1],'full_as_background',false);
ex.exp.CoPs.ctl.coherence = 1;
info = validateCoPsStimulusSelection(ex);
verifyEqual(testCase,double(info.nUniqueRequirements),3);
end

function testLocalModeAllowsExplicitSourceAndOutputOverrides(testCase)
opts = options(testCase,1);
out = invoke(testCase,'local','face',1,opts);
verifyEqual(testCase,out.options.source_root,opts.source_root);
verifyEqual(testCase,out.options.output_root,opts.output_root);
full = load(fullfile(out.sessions(1).images(1).fullFolder,'full_0001.mat'));
verifyEqual(testCase,full.full_tp,testCase.TestData.reference(1).full(:,:,1),'AbsTol',1e-8);
end

function testBundledPngsMatchTheirChecksumsAndInventory(testCase)
root = fullfile(testCase.TestData.repoRoot,'stimulus_sources');
manifest = jsondecode(fileread(fullfile(root,'manifest.json')));
files = manifest.files;
verifyEqual(testCase,sum([manifest.sets.count]),numel(files));
verifyLessThan(testCase,max([files.bytes]),100*1024^2);
for group = manifest.sets(:)'
    actual = dir(fullfile(root,group.folder,'*.png'));
    verifyNumElements(testCase,actual,group.count);
    verifyEqual(testCase,sum([actual.bytes]),group.bytes);
end
actualHashes = cell(numel(files),1);
actualBytes = zeros(numel(files),1);
digest = java.security.MessageDigest.getInstance('SHA-256');
for k=1:numel(files)
    filename = fullfile(root,strrep(files(k).path,'/',filesep));
    fid = fopen(filename,'rb');
    assert(fid>=0,'StimGenTest:MissingBundledPng','Cannot open %s.',filename);
    bytes = fread(fid,Inf,'*uint8'); fclose(fid);
    actualBytes(k) = numel(bytes);
    digest.update(bytes);
    actualHashes{k} = lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
verifyEqual(testCase,actualBytes,[files.bytes]');
verifyEqual(testCase,actualHashes,{files.sha256}');
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

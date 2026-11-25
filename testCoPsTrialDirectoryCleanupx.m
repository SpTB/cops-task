function tests = testCoPsTrialDirectoryCleanupx
tests = functiontests(localfunctions);
end

function setup(testCase)
folder=tempname; mkdir(folder);
testCase.TestData.folder=folder;
end

function teardown(testCase)
if isfolder(testCase.TestData.folder), rmdir(testCase.TestData.folder,'s'); end
end

function testKeepsPracticeDataAndRemovesOnlyRootCheckpoints(testCase)
folder=testCase.TestData.folder;
practice=fullfile(folder,'instruction_practice'); mkdir(practice);
Trials=struct('Eye',struct('v',ones(6,4),'t',1:4,'n',4)); %#ok<NASGU>
save(fullfile(practice,'practice1.mat'),'Trials');
save(fullfile(folder,'tr1.mat'),'Trials');
save(fullfile(folder,'session.mat'),'Trials');
before=pwd;
cleanupCoPsTrialDirectoryx(folder);
verifyEqual(testCase,pwd,before);
verifyTrue(testCase,isfolder(folder));
saved=load(fullfile(practice,'practice1.mat'));
verifyEqual(testCase,saved.Trials,Trials);
verifyFalse(testCase,isfile(fullfile(folder,'tr1.mat')));
verifyFalse(testCase,isfile(fullfile(folder,'session.mat')));
cleanupCoPsTrialDirectoryx(folder); % repeated cleanup also preserves practice
verifyTrue(testCase,isfile(fullfile(practice,'practice1.mat')));
end

function testRemovesDirectoryWhenNoPermanentDataRemain(testCase)
folder=testCase.TestData.folder;
Trials=struct('ID',1); %#ok<NASGU>
save(fullfile(folder,'tr1.mat'),'Trials');
cleanupCoPsTrialDirectoryx(folder);
verifyFalse(testCase,isfolder(folder));
cleanupCoPsTrialDirectoryx(folder); % already removed
end

function testRetainsEmptySubfolderAndOtherFiles(testCase)
folder=testCase.TestData.folder;
mkdir(fullfile(folder,'instruction_practice'));
cleanupCoPsTrialDirectoryx(folder);
verifyTrue(testCase,isfolder(fullfile(folder,'instruction_practice')));
fid=fopen(fullfile(folder,'notes.txt'),'w'); fprintf(fid,'keep'); fclose(fid);
cleanupCoPsTrialDirectoryx(folder);
verifyEqual(testCase,fileread(fullfile(folder,'notes.txt')),'keep');
end

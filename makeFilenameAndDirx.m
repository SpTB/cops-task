function [fname, dirName, trDir ] = makeFilenameAndDir(ex,fileSuffix)

% makes the filename of the current experiment file and (if needed) creates
% a new directory where to store it

% history
% 08/28/14  hn: wrote it
% 09/02/15  hn: included filePrefixes for kaki and lychee
% 02/02/16  hn: re-format date string to include a leading 0 in months
% 12/04/20  hn: included filePrefix for lemieux

if nargin<2
    fileSuffix = makeFilenameSuffix(ex);
end

% curr_date = datestr(date,26);
% dateString = [num2str(curr_date(1)) '.' num2str(curr_date(2)) '.'
% num2str(curr_date(3))]; % old version
dateString = strrep(datestr(date,26),'/','.');
%timeString=strrep(datestr(rem(now,1)),' ', '');
[a,b] = strtok(datestr(now,21),' ');
timeString = strrep(b,':','.');
timeString = strrep(timeString,' ','');
timeString = timeString(1:5);
if ~isfield(ex.Header,'animal') 
    filePrefix = input('please input the file prefix ("ma" for mango, "ki" for kiwi, "ka" for kaki, "ly" for lychee, "t" for testfile):  ','s');
else
    switch lower(ex.Header.animal)
        case 'barnum'
            filePrefix = 'ba';
        case 'mango'
            filePrefix = 'ma';
        case 'kiwi'
            filePrefix = 'ki';
        case 'kaki'
            filePrefix = 'ka';
        case 'lychee'
            filePrefix = 'ly';
        case 'lemieux'
            filePrefix = 'le';  
        case 'tempura'
            filePrefix = 'te';  
        case 'hummus'
            filePrefix = 'hu';  
        case 'shocktop'
            filePrefix = 'sh';      
         case 'jocamo'
            filePrefix = 'jo';      
                       
        case 'test'
            filePrefix = 't';
        otherwise 
            filePrefix = 'xx';
    end
end

if isfield(ex.Header,'SessionID')
    timeString = [ex.Header.SessionID '_' timeString];
end    
    
cur_dir = pwd;
switch filePrefix
    case 'ki'
        fname = ['ki_' timeString '.' fileSuffix '.mat'];
        trDir = ['ki_' timeString '.' fileSuffix ];
        if ~exist([ex.setup.dirRoot '/kiwi/' dateString])
            cd ([ex.setup.dirRoot '/kiwi'])
            mkdir(dateString)

        end
        dirName = [ex.setup.dirRoot '/kiwi/' dateString];
        cd(dirName)
        mkdir(trDir)
        cd(cur_dir)
        trDir = [dirName '/' trDir];
    case 'ma'
        fname = ['ma_' timeString '.' fileSuffix '.mat'];
        trDir = ['ma_' timeString '.' fileSuffix ];
        if ~exist([ex.setup.dirRoot '/mango/' dateString])
            cd([ex.setup.dirRoot '/mango'])
            mkdir(dateString)
        end

        dirName = [ex.setup.dirRoot '/mango/' dateString];
        cd(dirName)
        mkdir(trDir)
        cd(cur_dir)

        trDir = [dirName '/' trDir];
    case 'ka'
        fname = ['ka_' timeString '.' fileSuffix '.mat'];
        trDir = ['ka_' timeString '.' fileSuffix ];
        if ~exist([ex.setup.dirRoot '/kaki/' dateString])
            cd([ex.setup.dirRoot '/kaki'])
            mkdir(dateString)
        end

        dirName = [ex.setup.dirRoot '/kaki/' dateString];
        cd(dirName)
        mkdir(trDir)
        cd(cur_dir)

        trDir = [dirName '/' trDir];
    case 'ly'
        fname = ['ly_' timeString '.' fileSuffix '.mat'];
        trDir = ['ly_' timeString '.' fileSuffix ];
        if ~exist([ex.setup.dirRoot '/lychee/' dateString])
            cd([ex.setup.dirRoot '/lychee'])
            mkdir(dateString)
        end

        dirName = [ex.setup.dirRoot '/lychee/' dateString];
        cd(dirName)
        mkdir(trDir)
        cd(cur_dir)

        trDir = [dirName '/' trDir];
    case 'le'
        fname = ['le_' timeString '.' fileSuffix '.mat'];
        trDir = ['le_' timeString '.' fileSuffix ];
        if ~exist([ex.setup.dirRoot '/lemieux/' dateString])
            cd([ex.setup.dirRoot '/lemieux'])
            mkdir(dateString)
        end

        dirName = [ex.setup.dirRoot '/lemieux/' dateString];
        cd(dirName)
        mkdir(trDir)
        cd(cur_dir)

        trDir = [dirName '/' trDir];

    case 'te'
        fname = ['te_' timeString '.' fileSuffix '.mat'];
        trDir = ['te_' timeString '.' fileSuffix ];
        if ~exist([ex.setup.dirRoot '/tempura/' dateString])
            cd([ex.setup.dirRoot '/tempura'])
            mkdir(dateString)
        end

        dirName = [ex.setup.dirRoot '/tempura/' dateString];
        cd(dirName)
        mkdir(trDir)
        cd(cur_dir)

        trDir = [dirName '/' trDir];
    case 'hu'
        fname = ['hu_' timeString '.' fileSuffix '.mat'];
        trDir = ['hu_' timeString '.' fileSuffix ];
        if ~exist([ex.setup.dirRoot '/hummus/' dateString])
            cd([ex.setup.dirRoot '/hummus'])
            mkdir(dateString)
        end

        dirName = [ex.setup.dirRoot '/hummus/' dateString];
        cd(dirName)
        mkdir(trDir)
        cd(cur_dir)

        trDir = [dirName '/' trDir];
        
     case 'sh'
        fname = ['sh_' timeString '.' fileSuffix '.mat'];
        trDir = ['sh_' timeString '.' fileSuffix ];
        if ~exist([ex.setup.dirRoot '/shocktop/' dateString])
            cd([ex.setup.dirRoot '/shocktop'])
            mkdir(dateString)
        end

        dirName = [ex.setup.dirRoot '/shocktop/' dateString];
        cd(dirName)
        mkdir(trDir)
        cd(cur_dir)

        trDir = [dirName '/' trDir];     


    case 'ba'
        fname = ['ba_' timeString '.' fileSuffix '.mat'];
        trDir = ['ba_' timeString '.' fileSuffix ];
        if ~exist([ex.setup.dirRoot '/barnum/' dateString])
            cd([ex.setup.dirRoot '/barnum'])
            mkdir(dateString)
        end

        dirName = [ex.setup.dirRoot '/barnum/' dateString];
        cd(dirName)
        mkdir(trDir)
        cd(cur_dir)

        trDir = [dirName '/' trDir];
     case 'jo'
        fname = ['jo_' timeString '.' fileSuffix '.mat'];
        trDir = ['jo_' timeString '.' fileSuffix ];
        if ~exist([ex.setup.dirRoot '/jocamo/' dateString])
            cd([ex.setup.dirRoot '/jocamo'])
            mkdir(dateString)
        end

        dirName = [ex.setup.dirRoot '/jocamo/' dateString];
        cd(dirName)
        mkdir(trDir)
        cd(cur_dir)

        trDir = [dirName '/' trDir];
       
    otherwise
        fname = ['t_' timeString '.' fileSuffix '.mat'];  
        trDir = ['t_' timeString '.' fileSuffix ];
        if ~exist([ex.setup.dirRoot '/test/' dateString])
            cd ([ex.setup.dirRoot '/test'])            
            dateString

            mkdir(dateString)

        end
        dirName = [ex.setup.dirRoot '/test/' dateString];
        cd(dirName)
        mkdir(trDir)
        cd(cur_dir)
        trDir = [dirName '/' trDir];

end

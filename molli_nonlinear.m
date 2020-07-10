% Calculate T1 maps from MOLLI data
% 
% Daniel Bulte, IBME, University of Oxford, July 2019
%%
% this version uses the absolute value form of the model to fit the data,
% and uses a value of 300 in the 11th volume as a noise threshold (any
% voxel <300 in volume 11 is set to zero in the T1 map)

% Edited by E Bluemke July 2020 (questions? emma.bluemke@new.ox.ac.uk)

clear all
close all

%%%%%%%%%%%%%%%%%%%
disp('Select MOLLI Folder set')
dirName = uigetdir(); 
options = struct('recursive', true, 'verbose', true, 'loadCache', false);
[partitions, meta] = readDicomSeries(dirName, options);
 % Return values:
%   imagePartitions: Array of structs containing all partitions found
%   metaFilenames: Cell array of dicom filenames that contain no images

% Read image by partition index
% readDicomSeriesImage reads a dicom image (and optional dicominfo) from a
% dicom series partition that was found with the readDicomSeries function.
%
% This function can be used in two ways:
% [image, info] = readDicomSeriesImage(directory, partition):
% Reads a partition specified by the caller. partition should be one
% element of the imagePartitions structure returned by readDicomSeries.
% directory should be the same directory that was provided to
% readDicomSeries.
%
% The image return value will contain only the frames specified in the
% partition, typically in a 3D matrix. The type is the same as returned
% from dicomread (usually int16).
%
% The info return value is either a dicominfo structure in case of an
% enhanced dicom file, or a cell array containing dicominfo structures in
% case of a series of classic dicom files.
[image1, info1] = readDicomSeriesImage(dirName, partitions(1));

nbrow = size(image1,1);
nbcol = size(image1,2);
nbslice = size(image1, 3);
nbvols = length(partitions);
nbvoxels = nbrow*nbcol*nbslice;
nbseries = length(partitions);

% disp('Select MOLLI Folder set')
% mollidir = uigetdir(); 
% molli_orig=dicomreadVolume(mollidir);

%[stat,struc]=fileattrib('*'); % gives me the names of all of the files
%nbvols=size(struc); % gives me the number of files, and thus TI's

nbti = 11; % 11 TI's for MOLLI

%metadata = zeros(nbti,1);
tinv_acq = zeros(nbti,1);
ttrig_acq = zeros(nbti,1);


for i=1:nbti
    [image, info] = readDicomSeriesImage(dirName, partitions(i));
    metadata(i) = info{1,1}; % to get the dicom headers for every file (TI)
    
    tinv_acq(i)=metadata(i).InversionTime;  % builds a vector of all of the TI's
end

% % need to reorder the TI's in tinv(i), 11 TI's in MOLLI
[tinv,new_order] = sort(tinv_acq);

for k = 1:nbseries
    [image, info] = readDicomSeriesImage(dirName, partitions(k));
	dataTmp = image;
	dataTmp = double(squeeze(dataTmp));	
	for ss = 1:nbslice 
		dataTmp2(:,:,ss,k) = dataTmp(:,:,ss); 
    end
end 
for j = 1:nbseries
    ordernum=new_order(j)
    data(:,:,:,j)= dataTmp2(:,:,:,ordernum);
end

size(data)
        

% create a mask to speed up calc, thresholds data 300 in final volume
mask=data(:,:,:,11);
mask(le(mask,100))=0; % changed from 300 to 100 2020 July EB
mask(ge(mask,100))=1;


% initialise matrices 
t1vec = zeros(1,nbvoxels,'single');
slope = zeros(nbti,nbvoxels); % there are 11 TI's in the MOLLI sequence

%% Calculate T1

indechs = 1;

% create a 2D array with TI's as the 2nd dimension
for z=1:nbslice
    for y=1:nbcol
        for x=1:nbrow  
        if (mask(x,y,z)==1)
            slope(:,indechs) = data(x,y,z,:);
        end
        indechs = indechs + 1;
        end
    end 
end


fo = fitoptions('Method','NonlinearLeastSquares','Lower',[0,0,0],'Upper',[6000,12000,5000],'StartPoint',[1000,2000,1000]);

molli = fittype('abs(Axy - Bxy * exp(-tinv/tonestar))','dependent',{'y'},...
    'independent',{'tinv'},'coefficients',{'Axy','Bxy','tonestar'},'options',fo);


for i=1:nbvoxels
    recover = slope(:,i);
    i
    if recover(1)~=0
                f = fit(tinv,recover,molli); 
                coeffvals = coeffvalues(f);
                Tonestar =  coeffvals(3);
                t1vec(i)= Tonestar*(coeffvals(2)/coeffvals(1)-1); % LL correction

            if (isnan(t1vec(i)) || t1vec(i)<0 || isinf(t1vec(i) || t1vec(i)>8000)) % remove rubbish values, limit to 5sec max
                    t1vec(i)=0;
            end
    end
end

t1map = reshape(t1vec,nbrow,nbcol,nbslice);

figure
imagesc(t1map);
title(sprintf('%s-%d.png',dirName,i))
caxis([0,3500]);
colorbar
axis off
daspect([1 1 1])
saveas(gcf,sprintf('%s.png',dirName))


dicomt1map = uint16(reshape(t1map,[nbrow nbcol 1 nbslice])); % reshape undoes the squeeze, which removed the colour dimension

output_dcm = [dirName, '_MOLLI_T1_map.dcm'];
% output_nii = [loadpath '_MOLLI_T1_map.nii.gz'];
%cd(dirname)
dicomwrite(dicomt1map, output_dcm, metadata(1), 'CreateMode', 'Copy'); % save as a dicom, gets metadata from another dicom file
% niftiwrite(dicomt1map, output_nii, 'Compressed', true);

beep
%% end


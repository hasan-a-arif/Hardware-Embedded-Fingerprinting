%% NOISE EXTRACTION

% Block 1
fprintf('Locating Values below 100mv in raw dataset \n');
rawData = readmatrix('EP_Ard1.csv');
% rawData = readmatrix('EP_Ard2.csv');

L = length(rawData);
th_l = 100;
idealVal_l = 0;

% Locating consecutive low wave in data point above certain thershold
lowInd = find(rawData(1:L)<th_l);
lowVal = rawData(lowInd);
indexDiff_l = diff(lowInd);
indLow = find(indexDiff_l>2);
Dl = indLow(2) - indLow(1)

% Block 2
fprintf('Extracting Noise from Raw Dataset \n');
% Creating buffer for consecutive high wave from a certian high index to
% keep the data synchronous
temp_l = [];
for i = indLow(1)+1:length(lowVal)
    if i <= length(lowVal)
        temp_l = [temp_l, lowVal(i)];
    end
end

% Calculating noise by subrating the ideal value of a wave, Which is PWM in
% this case
Err_l = temp_l - idealVal_l;

% Creating a matric for low wave only and keeping the size of datapoint to 500 only
chunks = floor(length(Err_l)/Dl);
vectorMatrix_l = cell(chunks, 1);    
for i = 1:chunks
    start_idx = (i - 1) * Dl + 1;
    end_idx = min(i * Dl, length(Err_l));
 
    truncatedData_l = Err_l(start_idx:end_idx)';
    truncatedData_l = truncatedData_l(1:500);
    vectorMatrix_l{i, 1} = truncatedData_l;
end

% size(vectorMatrix_l)

% Converting the cells into row matrix
rowMatrix_l = horzcat(vectorMatrix_l{:});
rowMatrix_l = rowMatrix_l.'; 

% Insert a column of zeros in the first position for labelling the dataset
rowMatrix_l = [ones(size(rowMatrix_l, 1), 1), rowMatrix_l];

% Block 3
fprintf('Saving file \n');
fileID = fopen('EP_LowDataset_Ard1.tsv', 'w');
% fileID = fopen('EP_LowDataset_Ard2.tsv', 'w');

% Write the matrix to the file with desired precision
[row, col] = size(rowMatrix_l);
for i = 1:row
    for j = 1:col
        fprintf(fileID, '%.15f', rowMatrix_l(i,j));
        if j < col
            fprintf(fileID, '\t');
        end
    end
    fprintf(fileID, '\n');
end

fclose(fileID);
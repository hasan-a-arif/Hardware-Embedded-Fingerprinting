%% DATASET PREPARATION

% Read the first TSV file
data1 = readtable('EP_LowDataset_Ard1.tsv', 'FileType', 'text', 'Delimiter', '\t', 'ReadVariableNames', false);

% Read the second TSV file
data2 = readtable('EP_LowDataset_Ard2.tsv', 'FileType', 'text', 'Delimiter', '\t', 'ReadVariableNames', false);

% Extract data for train dataset, which consist of 80% data
subset_data1 = data1(1:720, :);
subset_data2 = data2(1:720, :);

% Extract data for test dataset, which consist of 20% data
% subset_data1 = data1(721:900, :);
% subset_data2 = data2(721:900, :);

% Combine the subsets vertically
combined_data = vertcat(subset_data1, subset_data2);

% Open the file for writing
fileID = fopen('EP_TestDataset_H.tsv', 'w');
fileID = fopen('EP_TrainDataset_H.tsv', 'w');

% Write the data to the file
[nrows, ncols] = size(combined_data);
for row = 1:nrows
    for col = 1:ncols
        % Check if the value is numeric
        if isnumeric(combined_data{row, col})
            % Format the numeric value with full precision
            value_str = sprintf('%.15f', combined_data{row, col});
        else
            % If it's not numeric, just get the string representation
            value_str = string(combined_data{row, col});
        end
        % Write the value to the file
        fprintf(fileID, '%s', value_str);
        
        % Add tab delimiter except for the last column
        if col < ncols
            fprintf(fileID, '\t');
        end
    end
    % Add newline character at the end of each row
    fprintf(fileID, '\n');
end

% Close the file
fclose(fileID);

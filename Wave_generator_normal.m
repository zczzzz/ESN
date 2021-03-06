
clear all; 
rand('seed', 15);
load('GResist');
load('LC');
load('pbma')
%% Create reservoir
%scale inputs and teacher attributes
nInputUnits = 1; nInternalUnits = 50; nOutputUnits = 4; 
%numElectrodes = 2; 
nForgetPoints = 100; % discard the first 100 points
sequenceLength = 1000;
inputScale = zeros(nInputUnits,1);
inputShift = zeros(nInputUnits,1);

for i = 1:nInputUnits
    inputScale(i,:) = 0.3; %0.3
    inputShift(i,:) = -0.2;%-0.2 necessary to correlate input and prediction/target
end

teacherScaling = zeros(nOutputUnits,1); teacherShift = zeros(nOutputUnits,1);

for i = 1:nOutputUnits
    teacherScaling(i,:) = 0.3;%0.3;
    teacherShift(i,:) = 0;%-0.2;
end

%% Create reservoir with correct scaling - best specrad 0.8948
esn = generate_esn(nInputUnits, nInternalUnits, nOutputUnits, ...
    'spectralRadius',0.6,'inputScaling',inputScale,'inputShift',inputShift, ...
    'teacherScaling',teacherScaling,'teacherShift',teacherShift,'feedbackScaling', 0, ...
    'type', 'plain_esn');

% esn = generate_esn(nInputUnits, nInternalUnits, nOutputUnits, ...
%     'spectralRadius',1,'inputScaling',inputScale,'inputShift',inputShift,'feedbackScaling', 0, ...
%     'type', 'plain_esn');


%% Assign input data and collect target output 
T = 10*(1/10);
Fs = 16666; %10x the freq being used
dt = 1/Fs;
t = 0:dt:T-dt;
%amplitude
A=1; %between 0-15

% Define input sequence
trainInputSequence(1,:)= A*sin(2*pi*10*t);

% configuration voltages - not really applicable as these don't change the
% function of the network (physically), changes in weights is much better
%trainInputSequence(2,:)= A*square(2*pi*10*t);
%trainInputSequence(3,:)= 0;%A*square(2*pi*20*t);

% Desired output
trainOutputSequence(1,:) = A*sawtooth(2*pi*10*t);
trainOutputSequence(2,:) = A*sin(2*pi*20*t);
trainOutputSequence(3,:) = A*square(2*pi*10*t);
trainOutputSequence(4,:) = A*cos(2*pi*10*t);
% Multiple outputs

%% Split training set
train_fraction = 0.5 ; % use 50% in training and 50% in testing
[trainInputSequence,testInputSequence ] = ...
    split_train_test(trainInputSequence',train_fraction);
[trainOutputSequence,testOutputSequence ] = ...
    split_train_test(trainOutputSequence',train_fraction);

%% train reservoir
%scale the reservoir using the 'spectral radius' i.e. absolute eigenvector
esn.internalWeights = esn.spectralRadius * esn.internalWeights_UnitSR;



%% Test - to observe if how well a simple statecollection of different
% sinewaves and cosines perform
% temp = zeros(16666,16);
% for i = 1:nInternalUnits+1
%     if i <= (nInternalUnits+1)/2 
%      temp(:,i) = A*sin(2*pi*10*i*t);
%     else
%         temp(:,i) = A*cos(2*pi*10*i*t);
%     end;
%     stateCollection(:,i) = temp(1:8233,i);
%   
% end

%%
%stateCollection = LC(1:8233,:); % test to see how the blob outputs compare

stateCollection = compute_statematrix(trainInputSequence, trainOutputSequence, esn, nForgetPoints) ;
teacherCollection = compute_teacher(trainOutputSequence, esn, nForgetPoints) ;

outputWeights = feval(esn.methodWeightCompute, stateCollection, teacherCollection) ;
outputSequence = stateCollection * outputWeights' ;
nOutputPoints = length(outputSequence(:,1)) ;
outputSequence = feval(esn.outputActivationFunction, outputSequence);
outputSequence = outputSequence - repmat(esn.teacherShift',[nOutputPoints 1]) ;
predictedTrainOutput = outputSequence / diag(esn.teacherScaling) ;

% Print plots
figure(1);
title('Trained ESN- saw');
hold on;
plot(trainOutputSequence(:,1), 'blue');
plot(trainInputSequence(:,1),'red');
plot(predictedTrainOutput(:,1),'black');

% extra figures for multiple outputs
figure(2);
title('2*sin');
hold on;
plot(trainOutputSequence(:,2), 'blue');
plot(trainInputSequence(:,1),'red');
plot(predictedTrainOutput(:,2),'black');

figure(3);
title('square');
hold on;
plot(trainOutputSequence(:,3), 'blue');
plot(trainInputSequence(:,1),'red');
plot(predictedTrainOutput(:,3),'black');

% 
figure(4);
title('cos');
hold on;
plot(trainOutputSequence(:,4), 'blue');
plot(trainInputSequence(:,1),'red');
plot(predictedTrainOutput(:,4),'black');


%% Test on new test set
stateCollection = compute_statematrix(testInputSequence, testOutputSequence, esn, nForgetPoints) ;
%stateCollection = resistor(1:8233,:);

outputSequence = [stateCollection]* outputWeights' ;
nOutputPoints = length(outputSequence(:,1)) ;
outputSequence = feval(esn.outputActivationFunction, outputSequence);
outputSequence = outputSequence - repmat(esn.teacherShift',[nOutputPoints 1]) ;
predictedTestOutput = outputSequence / diag(esn.teacherScaling) ;


%% Compute NRMSE error for both sets
 trainError = compute_NRMSE(predictedTrainOutput, trainOutputSequence); 
disp(sprintf('train NRMSE = %s', num2str(trainError)))
testError = compute_NRMSE(predictedTestOutput, testOutputSequence); 
disp(sprintf('test NRMSE = %s', num2str(testError)))

% Display Fast-fourier transform
figure;
temp_fft = abs(fft(stateCollection));
ft = temp_fft(1:length(stateCollection)/2,:);
f = Fs*(0:length(stateCollection)/2-1)/length(stateCollection);
plot(f,ft);
%grid on
xlim([0 100]);
title('Frequency response - FFT')
xlabel('Frequency (Hz)')
ylabel('|Y(f)|')

% power spectral density via fft
figure;
N = length(stateCollection);
xdft = fft(stateCollection);
xdft = xdft(1:N/2+1,:);
psdx = (1/(Fs*N)) * abs(xdft).^2;
psdx(2:end-1,:) = 2*psdx(2:end-1,:);
freq = 0:Fs/length(stateCollection):Fs/2;

plot(freq,10*log10(psdx))
grid on
xlim([0 100]);
title('Periodogram Using FFT')
xlabel('Frequency (Hz)')
ylabel('Power/Frequency (dB/Hz)')
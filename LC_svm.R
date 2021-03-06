#!/usr/bin/Rscript
  
##loading required libraries
library("ggplot2")
library("lattice") 
library("caret")
library("plyr")
library("rpart")
library("kernlab")
library(doMC)
registerDoMC(cores = 4)

sub_frac <- 0.1 #|> subtraining fraction to use for training
N_iter <- 20    #|> number of iterations for learning curve

## loading cleaned data
training <- read.table("clean_data/loan_train.txt", sep = "", header = TRUE)
testing <- read.table("clean_data/loan_test.txt", sep = "", header = TRUE)


## extract fraction of data and perfor hyperparameter tuning 
set.seed(300)
sub_data <- training[createDataPartition(y=training$loan_status, p = sub_frac, list = FALSE),]
training <- sub_data
#validation <- training[createDataPartition(y=sub_data$loan_status, p = 0.3, list=FALSE), ]


##----------------------------------- Experiment 1 ------------------------------------##
## Support Vector Machines
## Fit SVM model with two different kernels: Radial and Linear
TrainCtrl <- trainControl(method = "cv", number = 5, verbose = FALSE)


## Fit Radial Kernel----------------------------------------------------------
set.seed(300) 
SVMgridRad <- expand.grid(C = (1:10)*0.2 + 0.5, sigma = c(0.030,0.033))
model_svmRad <- train(factor(loan_status) ~ .,
                     data = training, 
                     method = "svmRadial",
                     trControl = TrainCtrl,
                     tuneGrid = SVMgridRad,
                     preProc = c("scale","center"),
                     verbose = FALSE)

best_sigma <- model_svmRad$bestTune$sigma
best_C <- model_svmRad$bestTune$C
prediction_svm_Rad <- predict(model_svmRad, testing)
con_mat_Rad <- confusionMatrix(prediction_svm_Rad, testing$loan_status)


#plot and save
pdf("figs/LC_svm_acc_cost_sigmaRad.pdf")
plot(model_svmRad)
dev.off()


## Fit Linear Kernel-------------------------------------------------------------------------
set.seed(300)
SVMgridLin <- expand.grid(C = (1:10)*0.2 + 0.5 ) 

model_svmLin <- train(factor(loan_status) ~ .,
                      data = training, 
                      method = 'svmLinear',
                      trControl = TrainCtrl,
                      tuneGrid = SVMgridLin,
                      preProc = c("scale","center"),
                      verbose = FALSE)

#best_sigma <- model_svm$bestTune$sigma
#best_C <- model_svm$bestTune$C
prediction_svm_Lin <- predict(model_svmLin, testing)
con_mat_Lin <- confusionMatrix(prediction_svm_Lin, testing$loan_status)

## compare two models
# collect models
result_models <- resamples(list(Radial=model_svmRad, Linear=model_svmLin))

# summarize the distributions
summary(result_models)

# boxplots of results
#plot and save
pdf("figs/LC_svm_model_compare.pdf")
bwplot(result_models)
dev.off()

## output confusion matrix
write.table(con_mat_Rad$table, file = "output/LC_confusion_mat_svmRad.txt", row.names = TRUE, col.names = TRUE, sep = "  ")
write.table(con_mat_Lin$table, file = "output/LC_confusion_mat_svmLin.txt", row.names = TRUE, col.names = TRUE, sep = "  ")
write.table(cbind(model_svmRad$bestTune,model_svmLin$bestTune),
            file = "output/LC_bestTune_svmRadLin.txt", row.names = TRUE, col.names = TRUE, sep = "  ")


##-------------------------------- Experiment 2 -------------------------------
# Learning Curve
# Vary trainig set size and and observe how accuracy of prediction affected

# initilzing empty array for some measures
test_accur <- 0
test_kap <- 0
train_accur <- 0
train_kap <- 0
cpu_time <- 0
data_size <- 0
set.seed(500)   #|> setting random seed
training1 <- training

TrainCtrl <- trainControl(method = "none")
SVMgrid <- expand.grid(sigma = best_sigma, C = best_C)


for (i in 1:N_iter) { 
  
  new_train <- training1 
  training1 <- new_train[createDataPartition(y = new_train$loan_status, p = 0.8, list = FALSE),]
  validation1 <- training[createDataPartition(y = training1$loan_status, p = 0.3, list = FALSE), ]
  
  
  start_time <- Sys.time() ## start the clock------------------------------------------------------
  svmFit <- train(factor(loan_status) ~ .,
                     data = training1, 
                     method = "svmRadial",
                     trControl = TrainCtrl,
                     tuneGrid = SVMgrid,
                     preProc = c("scale","center"),
                     verbose = FALSE)
  
  end_time <- Sys.time()  ## end the clock---------------------------------------------------------
  
  
  ## making a prediction
  prediction_svm_test <- predict(svmFit, testing, type = "raw")
  con_mat_test <- confusionMatrix(prediction_svm_test, testing$loan_status)
  
  prediction_svm_train <- predict(svmFit, validation1, type = "raw")
  con_mat_train <- confusionMatrix(prediction_svm_train, validation1$loan_status)
  
  cpu_time[i] <- round(as.numeric(end_time - start_time),3)
  data_size[i] <- nrow(training1)
  test_accur[i] <- round(as.numeric(con_mat_test$overall[1]),3)
  test_kap[i] <- round(as.numeric(con_mat_test$overall[2]),3)
  train_accur[i] <- round(as.numeric(con_mat_train$overall[1]),3)
  train_kap[i] <- round(as.numeric(con_mat_train$overall[2]),3)
}

results <- data.frame(test_accur,test_kap,train_accur,train_kap, cpu_time, data_size)
write.table(results, file = "output/LC_learning_results_svm.txt", row.names = TRUE, col.names = TRUE, sep = "  ")


## plot some results
pl <- ggplot(results, aes(x=data_size)) +
  geom_line(aes(y = train_accur, colour = "train")) + 
  geom_line(aes(y = test_accur, colour = "test")) +
  geom_point(aes(y = train_accur,colour = "train")) + 
  geom_point(aes(y = test_accur,colour = "test")) +
  theme_bw() +
  labs(title = "Learning Curve SVM LC", x = "Training Size", y = "Accuracy", color="") +
  theme(legend.position = c(0.6,0.8),
        axis.title = element_text(size = 16.0),
        axis.text = element_text(size=10, face = "bold"),
        plot.title = element_text(size = 15, hjust = 0.5),
        axis.text.x = element_text(colour="black"),
        axis.text.y = element_text(colour="black"))

#plot and save
png("figs/LC_svm_learning_curve.png", width = 5.0, height = 4.0, units = "in", res = 800)
pl
dev.off()




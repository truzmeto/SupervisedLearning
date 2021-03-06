#!/usr/bin/Rscript

#loading reuired libraries
library("ggplot2")
library("lattice") 
library("caret")
library("plyr")
library("rpart")
library(doMC)
registerDoMC(cores = 4)


sub_frac <- 0.2 #|> subtraining fraction to use for training
N_iter <- 20    #|> number of iterations for learning curve


## loading cleaned data
training <- read.table("clean_data/loan_train.txt", sep = "", header = TRUE)
testing <- read.table("clean_data/loan_test.txt", sep = "", header = TRUE)


## extract fraction of data and perfor hyperparameter tuning 
set.seed(300)
sub_data <- training[createDataPartition(y=training$loan_status, p = sub_frac, list = FALSE),]
training <- sub_data
validation <- training[createDataPartition(y=sub_data$loan_status, p = 0.3, list=FALSE), ]


##############################################################################################
##--------------------------------- Experiment 1 -------------------------------------------##
## Cross Validate
## Grow the tree. Apply post prunning to avoid overfitting

## building a model with trees
model_trees <- rpart(factor(loan_status) ~. , data = training,
                     method="class",
                     parms = list(split = "information"), #, prior = c(.55,.45))
                     control=rpart.control(minsplit = 5, cp = 0)) 

## predict on test set
prediction_test <- predict(model_trees, testing, type = "class")
con_mat_test <- confusionMatrix(prediction_test, testing$loan_status)
con_mat_test$overall

## predict on train sub set(validation)
prediction_train <- predict(model_trees, validation, type = "class")
con_mat_train <- confusionMatrix(prediction_train, validation$loan_status)
con_mat_train$overall

## plot xerror vs complexity parameter for original tree
png("figs/LC_tree_cp_xerror.png", width = 4.0, height = 4.0, units = "in", res = 800)
plotcp(model_trees)
dev.off()

## apply prunning using optimum values for "cp" and "nsplit" 
cp <- model_trees$cptable[which.min(model_trees$cptable[,"xerror"]),"CP"]
pruned_tree <- prune(model_trees, cp = cp)

## plotting pruned tree diagram
library(rpart.plot)
png("figs/LC_pruned_tree_diag.png", width = 12.0, height = 6.0, units = "in", res = 800)
rpart.plot(pruned_tree, fallen.leaves = FALSE, cex = 0.3, tweak = 1.6,
           shadow.col = "gray", sub = "Pruned Tree Diagram LC")
dev.off()

# predictiong with pruned tree on test set
prediction_pruned_test <- predict(pruned_tree, testing, type = "class")
con_mat_pruned_test <- confusionMatrix(prediction_pruned_test, testing$loan_status)

# predicting with pruned tree on validation set
prediction_pruned_train <- predict(pruned_tree, validation, type = "class")
con_mat_pruned_train <- confusionMatrix(prediction_pruned_train, validation$loan_status)
con_mat_pruned_train$overall

## summarize all pre and post pruning results via accuracy .......
results_tree <- data.frame(rbind(con_mat_test$overall, 
                               con_mat_train$overall,
                               con_mat_pruned_test$overall,
                               con_mat_pruned_train$overall),
                         row.names = c("ori_test","ori_train","pruned_test","pruned_train"))

write.table(results_tree, file = "output/LC_tree_pre_post_pruning_results.txt", row.names = TRUE, col.names = TRUE, sep = "  ")

## output confusion matrix
write.table(con_mat_pruned_test$table, file = "output/LC_confusion_mat_tree.txt", row.names = TRUE, col.names = TRUE, sep = "  ")


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
train_frac <- 0.8 
training1 <- training

for (i in 1:N_iter) { 
  
  new_train <- training1 
  training1 <- new_train[createDataPartition(y=new_train$loan_status, p = train_frac, list=FALSE),]

  start_time <- Sys.time() #start the clock---------------------------------------------------------

  ## building a model with trees
  model_trees <- rpart(factor(loan_status) ~. , data = training1,
                       method="class",
                       #control = ("maxdepth = 20"),
                       parms = list(split = "information"), #, prior = c(.55,.45))
                       control=rpart.control(minsplit = 5, cp = 0.0002))
  
  ## apply prunning 
  cp <- model_trees$cptable[which.min(model_trees$cptable[,"xerror"]),"CP"]
  pruned_tree <- prune(model_trees, cp = cp) 
  end_time <- Sys.time() # end the clock ---------------------------------------------------------

  
  # predictiong with pruned tree on test set
  prediction_pruned_test <- predict(pruned_tree, testing, type = "class")
  con_mat_pruned_test <- confusionMatrix(prediction_pruned_test, testing$loan_status)
  con_mat_pruned_test$overall
  
  # predicting with pruned tree on train sub set
  validation1 <- training1[createDataPartition(y=training1$loan_status, p = 0.3, list=FALSE),]
  prediction_pruned_train <- predict(pruned_tree, validation1, type = "class")
  con_mat_pruned_train <- confusionMatrix(prediction_pruned_train, validation1$loan_status)
  con_mat_pruned_train$overall
  
  ## save all size dependent variables  
  cpu_time[i] <- round(as.numeric(end_time - start_time),3)
  data_size[i] <- nrow(training1)
  test_accur[i] <- round(as.numeric(con_mat_pruned_test$overall[1]),3)
  test_kap[i] <- round(as.numeric(con_mat_pruned_test$overall[2]),3)
  train_accur[i] <- round(as.numeric(con_mat_pruned_train$overall[1]),3)
  train_kap[i] <- round(as.numeric(con_mat_pruned_train$overall[2]),3)
}

results <- data.frame(test_accur,test_kap,train_accur,train_kap, cpu_time, data_size)
write.table(results, file = "output/LC_learning_results_tree.txt", row.names = TRUE, col.names = TRUE, sep = "       ")


#plot some results
pl <- ggplot(results, aes(x=data_size)) +
      geom_line(aes(y = train_accur, colour = "train")) + 
      geom_line(aes(y = test_accur, colour = "test")) +
      geom_point(aes(y = train_accur,colour = "train")) + 
      geom_point(aes(y = test_accur,colour = "test")) +
      theme_bw() +
      ylim(0.65, .85) +
      #xlim(-0.01, ) +
      labs(title = "Learning Curve Prunned Tree Model LC", x = "Training Size", y = "Accuracy", color="") +
      theme(legend.position = c(0.2,0.8),
            axis.title = element_text(size = 16.0),
            axis.text = element_text(size=10, face = "bold"),
            plot.title = element_text(size = 15, hjust = 0.5),
            #text = element_text(family="Times New Roman"),
            axis.text.x = element_text(colour="black"),
            axis.text.y = element_text(colour="black"))

png("figs/LC_tree_learning_curve.png", width=5.0, height = 4.0, units = "in", res=800)
pl
dev.off()

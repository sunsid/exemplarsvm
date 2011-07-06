function voc_template(dataset_params, cls)
%% This is the main VOC driver script for both scenes and exemplars

models_name = dataset_params.models_name;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% EXEMPLAR INITIALIZATION %%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Initialize exemplars with the exemplar stream
e_stream_set = get_pascal_stream(dataset_params, cls);
efiles = exemplar_initialize(dataset_params, e_stream_set, ...
                             models_name, dataset_params.init_params);


%Load all of the initialized exemplars
CACHE_FILE = 1;
STRIP_FILE = 0;
models = load_all_models(dataset_params, cls, models_name, ...
                         efiles, CACHE_FILE, STRIP_FILE);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% EXEMPLAR TRAINING %%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Train each initialized exemplar 
if isfield(dataset_params,'mining_params')
  curparams = dataset_params.mining_params;

  cur_set = get_pascal_set(dataset_params, ...
                           curparams.set_name);
  
  if isfield(curparams,'set_maxk')
    cur_set = cur_set(1:min(length(cur_set), ...
                            curparams.set_maxk));
  end
    
  [tfiles, models_name] = train_all_exemplars(dataset_params, ...
                                              models, cur_set);  
  %Load the trained exemplars
  CACHE_FILE = 1;
  STRIP_FILE = 1;
  models = load_all_models(dataset_params, cls, models_name, ...
                           tfiles, CACHE_FILE, STRIP_FILE);
  
else
  fprintf(1,['Skipping training becuase dataset_params.mining_params not' ...
             ' present\n']);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% EXEMPLAR CROSS VALIDATION %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Apply trained exemplars on validation set
if isfield(dataset_params,'val_params')
  curparams = dataset_params.val_params;
  cur_set = get_pascal_set(dataset_params, ...
                           curparams.set_name);
  if isfield(curparams,'set_maxk')
    cur_set = cur_set(1:min(length(cur_set), ...
                            curparams.set_maxk));
  end

  dataset_params.params = curparams;;
  dataset_params.params.gt_function = @get_pascal_anno_function;
  val_files = apply_all_exemplars(dataset_params, models, cur_set, ...
                                  curparams.set_name);

  %Load validation results
  val_grid = load_result_grid(dataset_params, models, ...
                          curparams.set_name, val_files);

  val_struct = pool_results(dataset_params, models, val_grid);

  %Show all raw detections on test-set as a "memex browser"
  show_memex_browser(dataset_params, models, val_grid,...
                     cur_set, curparams.set_name);
  

  show_memex_browser2(dataset_params, models, val_struct,...
                     cur_set, curparams.set_name);


  %% Perform l.a.b.o.o. calibration and M-matrix estimation
  M = calibrate_and_estimate_M(dataset_params, models, val_grid);

else
  fprintf(1,['Skipping validation becuase dataset_params.val_params not' ...
             ' present\n']);
  M = [];
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% EXEMPLAR TESTING %%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Apply trained exemplars on test set
if isfield(dataset_params,'test_params')
  curparams = dataset_params.test_params;
  cur_set = get_pascal_set(dataset_params, ...
                           curparams.set_name);

  if isfield(curparams,'set_maxk')
    cur_set = cur_set(1:min(length(cur_set), ...
                            curparams.set_maxk));
  end
  
  if length(cur_set) == 0
    fprintf(1,'Warning, testset is empty\n');
    return;
  end

  %Apply on test set
  dataset_params.params = curparams;
  dataset_params.params.gt_function = [];
  test_files = apply_all_exemplars(dataset_params, models, cur_set, ...
                                  curparams.set_name);

  %Load test results
  test_grid = load_result_grid(dataset_params, models, ...
                               curparams.set_name, test_files);
  
  %Show all raw detections on test-set as a "memex browser"
  show_memex_browser(dataset_params, models, test_grid,...
                     cur_set, curparams.set_name);

  
else
  fprintf(1,['Skipping testing becuase dataset_params.test_params not' ...
             ' present\n']);
  
  %If testing is not performed, there is nothing left to do
  return;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% EXEMPLAR EVALUATION/DISPLAY %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Evaluation of uncalibrated SVM classifiers
M2 = [];
test_struct = pool_results(dataset_params, models, test_grid, M2);

show_memex_browser2(dataset_params, models, test_struct,...
                    cur_set, curparams.set_name);


if (dataset_params.SKIP_EVAL == 0)
  [results] = evaluate_pascal_voc_grid(dataset_params, ...
                                       models, test_grid, ...
                                       curparams.set_name, ...
                                       test_struct);
end

%%% Show top detections from uncalibrated SVM classifiers
% show_top_dets(dataset_params, models, test_grid,...
%               test_set, dataset_params.testset_name, ...
%               test_struct);

%If no calibration was performed, then we are done
if length(M) == 0
  return;
end

if (dataset_params.SKIP_EVAL == 0)

  %% Evaluation of l.a.b.o.o. afer training
  M2 = [];
  M2.betas = M.betas;
  test_struct = pool_results(dataset_params, models, test_grid, ...
                             M2);
  
  show_memex_browser2(dataset_params, models, test_struct,...
                      cur_set, curparams.set_name);

  [results] = evaluate_pascal_voc_grid(dataset_params, ...
                                       models, test_grid, ...
                                       curparams.set_name,...
                                       test_struct);
  
  %% Show top detections from l.a.b.o.o.
  %show_top_dets(dataset_params, models, test_grid,...
  %              test_set, dataset_params.testset_name, ...
  %              test_struct);
  
  %% Evaluation of laboo + M matrix
  test_struct = pool_results(dataset_params, models, test_grid, M);
  show_memex_browser2(dataset_params, models, test_struct,...
                      cur_set, curparams.set_name);

  [results] = evaluate_pascal_voc_grid(dataset_params, ...
                                       models, test_grid, ...
                                       curparams.set_name, ...
                                       test_struct);
  
  %% Show top detections for laboo + M matrix
  %show_top_dets(dataset_params, models, test_grid,...
  %              test_set, curparams.set_name, ...
  %              test_struct);
end

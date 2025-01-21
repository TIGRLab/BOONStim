# BOONStim Pipeline

## About

![boonstim_overview](https://github.com/TIGRLab/BOONStim/assets/54225067/572aaa33-f090-4de6-af27-9b98dcdef137)

## Code Organization
- **bin** contains run-time scripts that are called during the pipeline. 
- **config** contains default configuration settings that BOONStim uses to source the proper containers and run-time settings (i.e cluster configuration)
- **modules** kind of like nipype workflows, where we can subdivide the pipeline into components
- **resources** contains dependencies, third-party config (i.e MSMSulc), and Boutiques invocations. BOONStim will make available the resources directory to running processes (i.e running fMRIPrep w/BIDS-filter-files)
- **boonstim.nf** main entry-point for pipeline

## Requirements

BOONStim is run on the **Nextflow** framework. Nextflow is a framework that is designed for data-driven computational pipelines which makes it a good fit for BOONStim.

This allows BOONStim to be extensible and scalable, which is helpeful for running on HCP systems. This means to run BOONStim, you must have nextflow installed and configured to your system to access the nf entry scripts. You can find out about how to install Nextflow for your system [here](https://www.nextflow.io/). Note: To initiate DSL2 version of Nextflow set the following environment variable: NXF_VER=19.09.0-edge or anything newer.

### Weightfunction/ROI Config

BOONStim requires some setup to determine the region of interest for the optimization, as well as the weightfunction workflow itself. A default one is provided in this repo (under `resources/weightfunc/weightfunc.nf.config`). Here is a description of the relevant weightfunction files in `resources/weightfunc` that are currently used:

 - `roi_mask.nii.gz`: Volume-space mask for the chosen region of interest
 - `roi_inverse_mask.nii.gz`: Volume-space mask of network or brain without the chosen ROI(s)
 - `compute_roi_connectivity.nf`: Workflow that contains modules to clean, smooth, and merge the surface data and generate correlations with the inverse ROI masks
 - `make_roi_mask.nf`: Workflow that contains modules to take the volume-space ROI mask and project it to a surface-space symmetric binarized mask
 - `calculate_weightfunc.nf`: Overview workflow that collects the preprocessed derivatives and outputs a projected mask and weightfunction used to generate an optimized target

BOONStim will read from these files to determine the region to optimize over for targeting, and you can swap out the modules and ROIs currently available for your own purposes.

## Quickstart

Once you have nextflow set up on your system, you're just about good to go for running BOONStim. Then you just need to edit the config files for your purposes (MRI acquisition parameters, preprocessing parameters, target regions) and run the following to get BOONStim started:

```
nextflow run boonstim.nf \
  -c config/boonstim.nf.config \
  -c resources/weightfunc/weightfunc.nf.config \
  --bids <bids_path> \
  --out <output_path> \
  --cache_dir <cache_path> \
  --method bayesian \
  --subjects <subjects_file> \
  --fmriprep_invocation resources/invocations/fmriprep-20.2.0_invocation.json \
  --anat_invocation resources/invocations/fmriprep_anat_wf.json
```

A quick description of the example config/invocation files available:
- `config/boonstim.nf.config`: the config file describing folders used directly by BOONStim, ex. filepaths, optimization configs, resource paths
- `resources/weightfunc/weightfunc.nf.config`: the config file describing the resources needed for running the weightfunction including regions of interest and cleaning parameters
- `resources/invocations/fmriprep-20.2.0_invocation.json`: an example fmriprep invocation file that has mandatory parameters for preprocessing the fMRI data
- `resources/invocations/fmriprep_anat_wf.json`: an example fmriprep invocation file that has mandatory parameters for preprocessing the anatomical data

Detailed information on all parameters are available in the **Inputs** section below.

## Inputs

Input Arguments:

- `--bids`: the path to a valid bids dataset.
- `--out`: the path where the main outputs will be copied to.
- `--cache_dir`: the path where intermediate outputs for each pipeline step will be copied to.
- `--subjects`: optional line delimited text file of which subjects to run the pipeline on. If not supplied, all subjects in `--bids` will be run.

Workflow Arguments:

- `--method`: Optimization method to compute TMS optimal positioning. Options are `bayesian` or `grid`.
- `--bin`: The path to this repo's `bin` folder.
- `--coil`: The path to a compressed nifti containing the information for the coil to use.
- `--license`: The path to a valid freesurfer license to run fmriprep with.

Module Arguments:

- `--fmriprep`: The path to an fmriprep singularity container, version >= 20.2.0.
- `--fmriprep_descriptor`: The path to an fmriprep boutiques descriptor file with fmriprep custom argument mappings.
- `--fmriprep_invocation`: The path to an fmriprep boutiques invocation file with arguments to invoke fmriprep step with in the pipeline.
- `--fmriprep_anat_invocation`: The path to an fmriprep boutiques invocation file with arguments to invoke fmriprep (anatomical) step with in the pipeline.
- `--ciftify`: The path to a ciftify singularity container, version >= 1.3.0.
- `--ciftify_descriptor`: The path to a ciftify boutiques descriptor file with ciftify custom argument mappings.
- `--ciftify_invocation`: The path to a ciftify boutiques invocation file with arguments to invoke ciftify step with in the pipeline.


## Cache


If you check out `processes.nf.config` you will see something like:

```
withName: run_fmriprep{
        executor = "${engine}"
        time = "48:00:00"
        cpus = 36
        queue = {get_partition(task.time)}
        errorStrategy = {task.attempt == 3 ? "finish" : "retry"}
        storeDir = cacheDir("run_fmriprep")
        scratch = true

    }
```

Whenever `storeDir` is specified it means caching will be used. The `cacheDir` function will take the `--cache_dir` command line argument and create a sub-directory there with the `run_fmriprep` sub-directory.

If you look at the folder contents of `--cache_dir`:

```
apply_precentral           fmriprep_anat                 project_mask2surf
bayesian_optimization      generate_parcellation         qc_cortical_distance
brainsight_transform       get_coil_cortical_distance    qc_imgs
calculate_roi_correlation  get_cortical_distance_masked  qc_parameteric_surf
centroid_project2vol       get_ratio                     run_fmriprep
ciftify                    get_scalp_seed                select_mshbm_roi
cifti_smooth               get_stokes_cf                 sulcmap_resampled
clean_img                  grid_optimization             te_project2vol
clean_img_v2               join_distmaps                 tetrahedral_projection
compute_weighted_centroid  join_surface_coordinates      tetrahedral_roi_projection
convert_fs2gifti           localite_transform            threshold_weightfunc
create_surface_html        make_symmetric_dscalar        update_msh
dilate_mask                mri2mesh                      weightfunc_mask
dilate_mt_roi              msm_sulc
evaluate_fem               optimize_coil

```

You'll see that each of these directories correspond to a `cacheDir(<ARG>)` referring to the stored outputs from a particular process.

This means if BOONStim crashes, it will not repeat jobs like mri2mesh, fMRIPrep, Ciftify, optimization. 

## Outputs

Outputs of BOONStim are specified using the `--out` flag.

Inside here you'll see the following folders:
- boonstim
- ciftify
- fmriprep
- freesurfer

In particular `boonstim` contains the targeting outputs:

```
sub-01
├── fs_sub-01
├── m2m_sub-01
├── results
│   ├── sub-01_brainsight.csv
│   ├── sub-01_history.txt
│   ├── sub-01_localite.csv
│   ├── sub-01_optimized_coil.geo
│   └── sub-01_optimized_fields.msh
├── sub-01.left_knob_scalefactor.txt
├── sub-01.right_knob_scalefactor.txt
├── sub-01_T1fs_conform.nii.gz
└── T1w
    ├── sub-01.L.midthickness.surf.gii
   ...

```

Importantly:
- `results/` contains:
    - `_brainsight.csv` and `_localite.csv` which contains coordinate information
    - `_optimized_fields.msh` is a GMSH `msh` containing the optimized simulation results
    - `_optimized_coil.geo` is a GMSH script to generate a figure of where the optimal placement of the targeting coil is
    - `(left|right)_knob_scalefactor.txt` - contains the Stokes correction factor using a canonical left/right hand-knob coordinate
    - `_T1fs_conform.nii.gz` - contains a NIFTI file in the same space as the FEM used for running simulations

## Quality Control Outputs

All QC outputs are automatically generated as part of BOONStim.

1. fMRIPrep
2. Ciftify
3. mri2mesh
4. Cortical Distance Measurements
5. Optimization Result

#### fMRIprep

**LOCATION**: `$out/fmriprep/${subject}.html`

Info on fmriprep QC available on [fmriprep's documentation](https://fmriprep.org/en/stable/outputs.html#visual-reports) and [TIGRLab documentation](http://imaging-genetics.camh.ca/documentation/#/resources/Pipeline-QC-guide?id=fmriprep-functional).


#### Ciftify

**LOCATION**: `${out}/ciftify/qc_*`

Info on ciftify QC available on [ciftify's documentation](https://edickie.github.io/ciftify/#/) and [TIGRLab documentation](http://imaging-genetics.camh.ca/documentation/#/resources/Pipeline-QC-guide?id=ciftify).

#### mri2mesh

**LOCATION**: `${out}/boonstim/${subject}/`

This can be done similarily to standard Freesurfer QC. Results can be found in `${subject}/fs_${subject}` and `${subject}/m2m_${subject}` directories. 

You can load in the `fs_<subject>/surf/{white,pial}.{lh.rh}` files alongside the `<subject>_T1fs_conform.nii.gz` file to view the surface quality of the mri2mesh Freesurfer run.

#### Cortical Distance Measurements

**LOCATION**: `${out}/boonstim/${subject}/results/${id_string}.html`

Where `${id_string}` is a unique identifier for a given ROI`(i.e ${subject}_${hemisphere}_${roi})`

#### Optimization Results

**LOCATION**: `${out}/boonstim/${subject}/results/${subject}_optimized_*`

Optimization results can be found in `outputs/boonstim/<SUBJECT>/results` as the `<SUBJECT>_optimized_{coil,geo}*` files. You can load both in as follows:


```
gmsh *optimized*
```


## Credit
This pipeline was conceptualized and developed by Jerrold Jeyachandra ([@jerdra](https://github.com/jerdra)). 

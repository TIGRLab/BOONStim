nextflow.enable.dsl=2
import groovy.util.FileNameByRegexFinder

process modify_config{

    label 'ciftify'
    
    input:
    tuple val(sub), val(run), path(dtseries), path(confounds), path(config)

    output:
    tuple val(sub), val(run), path(dtseries),\
    path(confounds), path("${sub}_${run}_cleanconfig.json"),\
    emit: config

    shell:
    '''
    #!/usr/bin/env python

    import pandas as pd
    import numpy as np
    import json

    # Pull steady state index
    df = pd.read_csv("!{confounds}", delimiter="\\t")
    steady_cols = [c for c in df.columns if "steady" in c]

    # Write result into JSON file
    with open("!{config}","r") as j:
        jdict = json.load(j)

    if steady_cols:
        steady_df = df[[c for c in df.columns if "steady" in c]].sum(axis=1).diff()
        steady_ind = np.where(steady_df < 0)[0]

        if np.any(steady_ind):
            jdict["--drop-dummy-TRs"] = int(steady_ind[0])
    
    with open("!{sub}_!{run}_cleanconfig.json","w") as j:
        json.dump(jdict,j,indent=3)

    '''
}

process clean_img{

    label 'ciftify'

    input:
    tuple val(sub), val(run), path(dtseries), path(confound), path(config)

    output:
    tuple val(sub), val(run), path("${sub}_${run}_clean.dtseries.nii"), emit: clean_dtseries

    shell:
    '''

    ciftify_clean_img --clean-config=!{config} \
                        --confounds-tsv=!{confound} \
                        !{dtseries} \
                        --output-file !{sub}_!{run}_clean.dtseries.nii
    '''

}

// ADDED 2021-04-12
process clean_img_v2{

    label 'ciftify'
    containerOptions "-B ${params.resources}/confounds:/confounds"

    input:
    tuple val(sub), val(run), path(dtseries), path(confound), path(config)

    output:
    tuple val(sub), val(run), path("${sub}_${run}_clean.dtseries.nii"), emit: clean_dtseries

    shell:
    '''
    #!/bin/bash

    export PYTHONPATH=${PYTHONPATH}:/confounds/multiband-censoring-comparisons/

    # Convert
    wb_command -cifti-convert -to-nifti !{dtseries} !{sub}_!{run}.nii.gz

    python /confounds/clean_img.py !{sub}_!{run}.nii.gz !{confound} !{config} \
			    !{dtseries} \
                            --method base \
                            $(pwd)/!{sub}_!{run}_clean
    '''

}

process smooth_img{

    label 'connectome'

    input:
    tuple val(sub), val(run), path(dtseries), path(left), path(right)

    output:
    tuple val(sub), val(run), path("${sub}_${run}_clean_smooth.dtseries.nii"), emit: smooth_dtseries

    shell:
    '''

    wb_command -cifti-smoothing \
                !{dtseries} \
                6 6 COLUMN \
                -left-surface !{left} \
                -right-surface !{right} \
                "!{sub}_!{run}_clean_smooth.dtseries.nii"
    '''
}

process merge_imgs{

    label 'connectome'

    input:
    tuple val(sub), path("smooth_img*.dtseries.nii")

    output:
    tuple val(sub), path("${sub}_cleaned_smoothed_merged.dtseries.nii"), emit: merged_dtseries

    shell:
    '''
    find . -mindepth 1 -maxdepth 1 -type l -name "*dtseries.nii" | sort | xargs -I {} \
        echo -cifti {} | xargs \
        wb_command -cifti-merge !{sub}_cleaned_smoothed_merged.dtseries.nii
    '''

}

process calculate_roi_correlation{

    label 'connectome'

    input:
    tuple val(sub), path(dtseries), path(left_shape), path(right_shape)

    output:
    tuple val(sub), path("${sub}_correlation.dscalar.nii"), emit: corr_dscalar

    shell:
    '''
    wb_command -cifti-average-roi-correlation \
                !{sub}_correlation.dscalar.nii \
                -left-roi !{left_shape} \
                -right-roi !{right_shape} \
                -cifti !{dtseries}
    '''

}

process split_cifti{

    label 'connectome'

    input:
    tuple val(sub), path(dscalar)

    output:
    tuple val(sub), path('L.shape.gii'), emit: left_shape
    tuple val(sub), path('R.shape.gii'), emit: right_shape

    shell:
    '''
    wb_command -cifti-separate \
                !{dscalar} \
                COLUMN \
                -metric CORTEX_LEFT L.shape.gii \
                -metric CORTEX_RIGHT R.shape.gii
    '''

}

process mask_cortex{

    label 'connectome'

    input:
    tuple val(sub), path(shape)

    output:
    tuple val(sub), path("masked.${shape}"), emit: masked_shape

    shell:
    '''
    wb_command -metric-math \
                "x*0" \
                -var "x" !{shape} \
                masked.!{shape}
    '''

}

process create_dense{

    label 'connectome'

    input:
    tuple val(sub), path(left_shape), path(right_shape)

    output:
    tuple val(sub), path("${sub}.weightfunc.dscalar.nii"), emit: weightfunc

    shell:
    '''
    wb_command -cifti-create-dense-scalar \
                !{sub}.weightfunc.dscalar.nii \
                -left-metric !{left_shape} \
                -right-metric !{right_shape}
    '''

}

process project_left_mask2surf{

    label 'connectome'

    input:
    tuple val(sub), path(midthickness), path(white), path(pial), path(mask)

    output:
    tuple val(sub), path("${sub}_surfmask.L.shape.gii"), emit: surfmask

    shell:
    '''
    #!/bin/bash

    wb_command -volume-to-surface-mapping \
                !{mask} \
                !{midthickness} \
                -ribbon-constrained \
                !{white} \
                !{pial} \
                "!{sub}_surfmask.L.shape.gii"
    '''

}

process project_right_mask2surf{

    label 'connectome'

    input:
    tuple val(sub), path(midthickness), path(white), path(pial), path(mask)

    output:
    tuple val(sub), path("${sub}_surfmask.R.shape.gii"), emit: surfmask

    shell:
    '''
    #!/bin/bash

    wb_command -volume-to-surface-mapping \
                !{mask} \
                !{midthickness} \
                -ribbon-constrained \
                !{white} \
                !{pial} \
                "!{sub}_surfmask.R.shape.gii"
    '''

}

process remove_subcortical{

    label 'connectome'

    input:
    tuple val(sub), path(dscalar)

    output:
    tuple val(sub), path("${sub}.correlation_nosubcort.dscalar.nii"), emit: corr_dscalar

    shell:
    '''

    # Split without volume
    wb_command -cifti-separate !{dscalar} \
                COLUMN \
                -metric CORTEX_LEFT L.shape.gii \
                -metric CORTEX_RIGHT R.shape.gii

    # Join
    wb_command -cifti-create-dense-scalar \
                !{sub}.correlation_nosubcort.dscalar.nii \
                -left-metric L.shape.gii \
                -right-metric R.shape.gii
    '''

}

workflow calculate_weightfunc_wf {

    take:
        derivatives

    main:

        // Project mask into surface space for the particular subject
        left_surfs = derivatives
                        .map{s,f,c ->   [
                                            s,
                                            "${c}/MNINonLinear/fsaverage_LR32k/${s}.L.midthickness.32k_fs_LR.surf.gii",
                                            "${c}/MNINonLinear/fsaverage_LR32k/${s}.L.white.32k_fs_LR.surf.gii",
                                            "${c}/MNINonLinear/fsaverage_LR32k/${s}.L.pial.32k_fs_LR.surf.gii",
                                            "${params.inverse_mask}"
                                        ]
                            }
        project_left_mask2surf(left_surfs)

        right_surfs = derivatives
                        .map{s,f,c ->   [
                                            s,
                                            "${c}/MNINonLinear/fsaverage_LR32k/${s}.R.midthickness.32k_fs_LR.surf.gii",
                                            "${c}/MNINonLinear/fsaverage_LR32k/${s}.R.white.32k_fs_LR.surf.gii",
                                            "${c}/MNINonLinear/fsaverage_LR32k/${s}.R.pial.32k_fs_LR.surf.gii",
                                            "${params.inverse_mask}"
                                        ]
                            }
        project_right_mask2surf(right_surfs)

        // Pull confounds TSV as well as JSON file
        i_modify_config = derivatives
                            .map{s,f,c ->   [
                                                s,
                                                f,
                                                new FileNameByRegexFinder().getFileNames("${c}",".*MNINonLinear/Results/.*(REST|rest).*/.*dtseries.nii")

                                            ]
                                }
                            .transpose()
                            .map{ s,f,d ->  [
                                                s,f,d,
                                                ( d =~ /ses-[^_]*/ )[0],
                                                ( d =~ /ses-0._task.+?(?=(_desc|_Atlas))/ )[0][0]
                                            ]
                                }
                            .map{ s,f,d,ses,ident ->    [
                                                            s,d,
                                                            new FileNameByRegexFinder().getFileNames("$f/$ses/func", ".*${ident}.*confound.*tsv")[0],
                                                            "${params.clean_config}"
                                                        ]
                                }
                            .map{ s,d,conf,clean -> [
                                                        s,
                                                        ( d =~ /run-[^_]*/ )[0],
                                                        d,conf,clean
                                                    ]
                                }


        //Clean image
        modify_config(i_modify_config)
        clean_img_v2(modify_config.out.config)

        //Smooth image need cifti information
        cifti_buffer = derivatives.map{s,f,c -> [s,c]}
        smooth_input = clean_img_v2.out.clean_dtseries.combine(cifti_buffer, by:0)
                                .map{ s,r,i,c ->  [
                                                    s,r,i,
                                                    "${c}/MNINonLinear/fsaverage_LR32k/${s}.L.midthickness.32k_fs_LR.surf.gii",
                                                    "${c}/MNINonLinear/fsaverage_LR32k/${s}.R.midthickness.32k_fs_LR.surf.gii"
                                                ]
                                    }

        smooth_img(smooth_input)

        //Combine smoothed images
        //Will be a bottleneck here!
        merge_img_input = smooth_img.out.smooth_dtseries
                                    .groupTuple( by: 0 , sort: {it} )
                                    .map{ s,r,sm -> [ s, sm ] }
        merge_imgs(merge_img_input)

        //Compute correlation
        correlation_input = merge_imgs.out.merged_dtseries
                                        .join(project_left_mask2surf.out.surfmask, by:0 )
                                        .join(project_right_mask2surf.out.surfmask, by:0 )
        calculate_roi_correlation(correlation_input)

        // Remove subcortical regions
        remove_subcortical(calculate_roi_correlation.out.corr_dscalar)

        emit:
        weightfunc = remove_subcortical.out.corr_dscalar

}
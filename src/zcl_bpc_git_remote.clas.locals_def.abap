CLASS ltcl_bitbucket_history DEFINITION DEFERRED.
CLASS zcl_bpc_git_remote DEFINITION LOCAL FRIENDS ltcl_bitbucket_history.
CLASS ltcl_lfs_hash DEFINITION DEFERRED.
CLASS zcl_bpc_git_remote DEFINITION LOCAL FRIENDS ltcl_lfs_hash.

CLASS ltcl_root_folder DEFINITION DEFERRED.
CLASS zcl_bpc_git_remote DEFINITION LOCAL FRIENDS ltcl_root_folder.

CLASS ltcl_notebook_history DEFINITION DEFERRED.
CLASS zcl_bpc_git_remote DEFINITION LOCAL FRIENDS ltcl_notebook_history.

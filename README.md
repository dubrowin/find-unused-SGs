# find-unused-SGs
Find Unused Security Groups in an account
I wanted to be able to find Unused SGs in an account by region. Currently, the tool covers EC2, OpenSearch, Lambda, RDS, and ELB.  

I ran this tool in my CloudShell and so I didn't save all the files in /tmp/ because they would be removed when CloudShell exits.

    find-unused-sgs.sh -h
    
        Usage: find-unused-sgs.sh [ -d | --debug ] [ -h | --help ] [ -r | --region <region name, default is local region> ] [ -f | --force ] 
        -f | --force -- do not ask permission to continue to the next step
        -r | --region -- region if not the local region
        -d | --debug -- print additional information

## Known Issues
- It does not trap the default Security Group, but tries to remove it and then fails with an error.

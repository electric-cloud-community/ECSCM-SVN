package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.TestHelper
import spock.lang.Shared

class Update extends TestHelper {
    @Shared projectName
    @Shared checkoutProjectName
    @Shared commitProjectName
    @Shared updateProjectName
    @Shared revision
    static final String agentHost  = System.getenv('EFAGENT_HOST')    ?: 'efagent-svn'

    def doSetupSpec() {
        createConfig()
        def result
        result = createWrapperProject('CheckoutCode', ['CheckoutType', 'command', 'config', 'dest', 'FileName', 'IgnoreExternals', 'Revision_outpp', 'SubversionRevision', 'SubversionUrl'])
        assert result?.project
        checkoutProjectName = result?.project.projectName
        result = createWrapperProject('CommitChanges', ['command', 'CommitMessage', 'config', 'svnDirectory'])
        assert result?.project
        commitProjectName = result?.project.projectName
        result = createWrapperProject('Update', ['config', 'dest', 'revision'])
        assert result?.project
        updateProjectName = result?.project.projectName
    }

    def 'update'() {
        setup:
        def workspaces = [:]
        def files = [ 'test_commit', 'test_2/test_commit', 'test_2/test_4/test_commit' ]
        def configNameLocal = configName // https://issues.apache.org/jira/browse/GROOVY-5776
        def repoServerLocal = repoServer
        def result

        [ 'test_1_commit', 'test_1_update' ].each {
            result = runProcedure(
                checkoutProjectName,
                'CheckoutCode',
                [
                    config          : configNameLocal,
                    SubversionUrl   : "svn://${repoServerLocal}/test_1",
                    dest            : it,
                    Revision_outpp  : "/myJob/test_1_revision"
                ], [], agentHost, 3600
            )
            assert result?.outcome == 'success'
            workspaces[it] = dsl("getJobInfo(jobId: '${result.jobId}')").job?.workspace?.unix[0]
            assert workspaces[it]
            def prop = dsl("getProperty(propertyName: '/myJob/test_1_revision', jobId: '${result.jobId}')")
            revision = prop?.property?.value
            assert revision.toInteger() > 0
        }

        result = runProcedure(
            'ECSpec',
            'Files',
            [
                files   : files.join("\n"),
                action  : 'write',
                basedir : workspaces['test_1_commit'] + '/test_1_commit',
                content : "${revision}"
            ], [], agentHost, 3600
        )
        assert result?.outcome == 'success'
        files.each {
            def workdir = it.replaceAll('test_commit', '')
            result = runProcedure(
                commitProjectName,
                'CommitChanges',
                [
                    config          : configNameLocal, // https://issues.apache.org/jira/browse/GROOVY-5776
                    CommitMessage   : "Fresh files at revision #" + revision,
                    svnDirectory    :  workspaces['test_1_commit'] + '/test_1_commit/' + workdir,
                ], [], agentHost, 3600
            )
            assert result?.outcome == 'success'
        }

        when:
        result = runProcedure(
            updateProjectName,
            'Update',
            [
                config          : configName,
                dest            : workspaces['test_1_update'] + "/test_1_update",
            ], [], agentHost, 3600
        )
        then: 'Procedure runs'
        assert result?.outcome == 'success'
        when:
        result = runProcedure(
            'ECSpec',
            'Files',
            [
                files   : files.join("\n"),
                action  : 'read',
                basedir : workspaces['test_1_update'] + '/test_1_update'
            ], [], agentHost, 3600
        )
        then:
        assert result?.outcome == 'success'
    }
}

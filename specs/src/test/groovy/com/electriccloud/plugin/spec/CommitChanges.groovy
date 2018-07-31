package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.TestHelper
import spock.lang.Shared

class CommitChanges extends TestHelper {
    @Shared projectName
    @Shared checkoutProjectName

    def doSetupSpec() {
        createConfig()
        def result = createWrapperProject('CheckoutCode', ['CheckoutType', 'command', 'config', 'dest', 'FileName', 'IgnoreExternals', 'Revision_outpp', 'SubversionRevision', 'SubversionUrl'])
        assert result?.project
        checkoutProjectName = result?.project.projectName
        result = createWrapperProject('CommitChanges', ['command', 'CommitMessage', 'config', 'svnDirectory'])
        assert result?.project
        projectName = result?.project.projectName

    }

    def 'commitChanges'() {
        setup:
        def files = [ 'test_commit', 'test_2/test_commit', 'test_2/test_4/test_commit' ]

        def result = runProcedure(
            checkoutProjectName,
            'CheckoutCode',
            [
                config          : configName,
                SubversionUrl   : "svn://${repoServer}/test_1",
                dest            : "test_1",
                Revision_outpp  : "/myJob/test_1_revision"
            ], [], null, 3600
        )
        assert result?.outcome == 'success'
        def workspace = dsl("getJobInfo(jobId: '${result.jobId}')").job?.workspace?.unix[0]
        assert workspace
        def revision = dsl("getProperty(propertyName: '/myJob/test_1_revision', jobId: '${result.jobId}')").property?.value
        assert revision.toInteger() > 0

        result = runProcedure(
            'ECSpec',
            'Files',
            [
                files   : files.join("\n"),
                action  : 'write',
                basedir : workspace + '/test_1',
                content : "at revision ${revision}\n"
            ], [], null, 3600
        )
        assert result?.outcome == 'success'
        def configNameLocal = configName // https://issues.apache.org/jira/browse/GROOVY-5776
        when:
        files.each {
            def workdir = it.replaceAll('test_commit', '')
            result = runProcedure(
                projectName,
                'CommitChanges',
                [
                    config          : configNameLocal, // https://issues.apache.org/jira/browse/GROOVY-5776
                    CommitMessage   : "Fresh files at revision #" + revision,
                    svnDirectory    :  workspace + '/test_1/' + workdir,
                ], [], null, 3600
            )
            assert result?.outcome == 'success'
        }
        result = runProcedure(
            checkoutProjectName,
            'CheckoutCode',
            [
                config          : configName,
                SubversionUrl   : "svn://${repoServer}/test_1",
                dest            : "test_1_checkout_after_commit",
                Revision_outpp  : "/myJob/test_1_revision"
            ], [], null, 3600
        )
        workspace = dsl("getJobInfo(jobId: '${result.jobId}')").job?.workspace?.unix[0]
        then:
        assert result?.outcome == 'success'
        assert workspace

        when:
        result = runProcedure(
            'ECSpec',
            'Files',
            [
                files   : files.join("\n"),
                action  : 'read',
                basedir : workspace + '/test_1_checkout_after_commit'
            ], [], null, 3600
        )
        then:
        assert result?.outcome == 'success'
        files.grep { dsl("getProperty(propertyName: '/myJob/result/${it}', jobId: '${result.jobId}')").property?.value =~ /at revision (\d+)/ }.size() == files.size()
    }
}

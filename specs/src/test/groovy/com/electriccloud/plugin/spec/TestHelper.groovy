package com.electriccloud.plugin.spec

import com.electriccloud.spec.PluginSpockTestSupport
import sun.reflect.generics.reflectiveObjects.NotImplementedException

class TestHelper extends PluginSpockTestSupport {
    static final String pluginName = 'ECSCM-SVN'
    static final String configName = System.getenv('SVN_CONFIG_NAME') ?: 'spec-test'
    static final String repoServer = System.getenv('SVN_REPO_SERVER') ?: 'svnserver'
    static final String agentHost  = System.getenv('EFAGENT_HOST')    ?: 'efagent-svn'
    static final String agentPort  = System.getenv('EFAGENT_PORT')    ?: '7808'

    def deleteConfig() {
        deleteConfiguration(pluginName, getConfigName())
    }

    def createConfig() {

        def pluginConfig = [
            config          : configName,
            credential      : configName,
            credentialType  : 'password',
            desc            : 'Spec config',
        ]

        assert createResource(agentHost, agentPort).resource?.resourceName == agentHost

        def credentials = [[credentialName: configName, userName: 'user1', password: 'user1']]

        if (doesConfExist('/plugins/ECSCM/project/scm_cfgs', configName)) {
            if (System.getenv('RECREATE_CONFIG')) {
                deleteConfiguration(pluginName, configName)
            }
            else {
                println "Configuration $configName exists"
                return
            }
        }

        def result = runProcedure("/plugins/${pluginName}/project", 'CreateConfiguration', pluginConfig, credentials)
        assert result.outcome == 'success'
    }

    def createWrapperProject (procedureName, argNames) {
        def result = dslFile "dsl/fileProcedures.dsl", [ resourceName: agentHost ]
        assert result?.project
        dsl '''
            def argNames = args.argNames
            def procedureName = args.procedureName
            def pluginName = args.pluginName
            def resName = args.resourceName

            project "EC Spec Test ${pluginName} - ${procedureName} @ ${resName}", {
                procedure "${procedureName}", {
                    resourceName = resName
                    argNames.each { argName ->
                        formalParameter "${argName}"
                    }
                    step "${procedureName}", {
                        resourceName = resName
                        subproject = "/plugins/${pluginName}/project"
                        subprocedure = "${procedureName}"
                        argNames.each { argName ->
                            actualParameter "${argName}", { value = "\\$[${argName}]" }
                        }
                    }
                }
            }
            ''', [ procedureName: procedureName, argNames: argNames, pluginName: pluginName, resourceName: agentHost ]
    }

    def createResource (String host, String port) {
        def res = dsl """
          resource '$host', {
            hostName = '$host'
            port     = '$port'
          }
        """
        sleep(10 * 1000)
        println res.dump()
        return res
        // Giving some rest to container
    }
}

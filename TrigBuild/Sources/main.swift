//
//  main.swift
//  Trigger
//
//  Created by Tom Woodley on 12/04/2023.
//

import Foundation
import AppStoreConnect_Swift_SDK

struct WorkflowsResponse: Decodable {
    let data: [Data]

    struct Data: Decodable {
        let id: String
    }
}


func startWorkflow(in repo: String, with issuerID: String, _ privateKeyID: String, _ privateKey: String) async throws {
    let config = APIConfiguration(
        issuerID: issuerID,
        privateKeyID: issuerID,
        privateKey: privateKeyID)
    let provider = APIProvider(configuration: config)

    let producstEndpoint = APIEndpoint
        .v1
        .ciProducts
        .get(parameters: .init(filterProductType: [.app], include: [.primaryRepositories]))

    let productResponse = try await provider.request(producstEndpoint)
    
    guard let repositoryId: String = productResponse
        .included?
        .compactMap({ includedItem in
            switch includedItem {
            case .scmRepository(let scmData) where scmData.attributes?.repositoryName == repo:
                return scmData.id
            default: return nil
            }
        })
            .first,
          
        let productId = productResponse.data.first(where: {
            $0.relationships?.primaryRepositories?.data?.contains { $0.id == repositoryId } == true
        })?.id else { return }
    
    let allWorkflowsEndpoint = APIEndpoint
            .v1
            .ciProducts
            .id(productId)
            .relationships
            .workflows

    let workflows = try await provider
        .request(
            Request<WorkflowsResponse>(
                method: "GET",
                path: allWorkflowsEndpoint.path
            )
        )
    
    guard let workflowId = workflows.data.first?.id else {
            return
        }

    let workflowEndpoint = APIEndpoint
        .v1
        .ciWorkflows
        .id(workflowId)
        .get()

    let workflow = try await provider.request(workflowEndpoint).data
    
    let requestRelationships = CiBuildRunCreateRequest
        .Data
        .Relationships(workflow: .init(data: .init(type: .ciWorkflows, id: workflow.id)))
    let requestData = CiBuildRunCreateRequest.Data(
        type: .ciBuildRuns,
        relationships: requestRelationships
    )
    let buildRunCreateRequest = CiBuildRunCreateRequest(data: requestData)

    let workflowRun = APIEndpoint
        .v1
        .ciBuildRuns
        .post(buildRunCreateRequest)
    
    print("About to make request")
    _ = try await provider.request(workflowRun)
}

print(CommandLine.arguments)
assert(CommandLine.arguments.count == 4)

try? await startWorkflow(in: "UniGrade", with: CommandLine.arguments[1], CommandLine.arguments[2], CommandLine.arguments[3])
print("Request Made - Starting XCode Cloud Build")

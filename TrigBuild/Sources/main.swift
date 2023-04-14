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
    print("Starting process")
    let config = APIConfiguration(
        issuerID: issuerID,
        privateKeyID: privateKeyID,
        privateKey: privateKey)
    let provider = APIProvider(configuration: config)

    print("Config & Provider Generated")

    let producstEndpoint = APIEndpoint
        .v1
        .ciProducts
        .get(parameters: .init(filterProductType: [.app], include: [.primaryRepositories]))

    print("Created Endpoint")

    let productResponse = try await provider.request(producstEndpoint)

    print("Provider Response Recieved")
    
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

    var workflows: WorkflowsResponse

    do {
        workflows = try await provider
        .request(
            Request<WorkflowsResponse>(
                method: "GET",
                path: allWorkflowsEndpoint.path
            )
        )
        print("Workflow Response Recieved")
    } catch APIProvider.Error.requestFailure(let statusCode, let errorResponse, _) {
        print("Request failed with statuscode: \(statusCode) and the following errors:")
        errorResponse?.errors?.forEach({ error in
            print("Error code: \(error.code)")
            print("Error title: \(error.title)")
            print("Error detail: \(error.detail)")
        })
        exit(1)
    } catch {
        print("Something went wrong: \(error.localizedDescription)")
        exit(1)
    }
    
    guard let workflowId = workflows.data.first?.id else {
            return
        }

    let workflowEndpoint = APIEndpoint
        .v1
        .ciWorkflows
        .id(workflowId)
        .get()

    let workflow: CiWorkflow

    do {
        workflow = try await provider.request(workflowEndpoint).data
        print("Workflow Endpoint Recieved")
    } catch APIProvider.Error.requestFailure(let statusCode, let errorResponse, _) {
        print("Request failed with statuscode: \(statusCode) and the following errors:")
        errorResponse?.errors?.forEach({ error in
            print("Error code: \(error.code)")
            print("Error title: \(error.title)")
            print("Error detail: \(error.detail)")
        })
        exit(1)
    } catch {
        print("Something went wrong: \(error.localizedDescription)")
        exit(1)
    }

    print("Workflow Endpoint Recieved")
    
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
    do {
        try await provider.request(workflowRun)
        print("Request Made - Starting XCode Cloud Build")
    } catch APIProvider.Error.requestFailure(let statusCode, let errorResponse, _) {
        print("Request failed with statuscode: \(statusCode) and the following errors:")
        errorResponse?.errors?.forEach({ error in
            print("Error code: \(error.code)")
            print("Error title: \(error.title)")
            print("Error detail: \(error.detail)")
        })
        exit(1)
    } catch {
        print("Decoding error but this usually is sucessful at making the call anyway")
    }
}

print(CommandLine.arguments)
assert(CommandLine.arguments.count == 4)

try await startWorkflow(in: "UniGrade", with: CommandLine.arguments[1], CommandLine.arguments[2], CommandLine.arguments[3])
